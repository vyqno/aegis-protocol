// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ReceiverTemplate} from "../interfaces/ReceiverTemplate.sol";
import {IAegisVault} from "../interfaces/IAegisVault.sol";
import {IRiskRegistry} from "../interfaces/IRiskRegistry.sol";
import {IStrategyRouter} from "../interfaces/IStrategyRouter.sol";
import {IWorldIdGate} from "../interfaces/IWorldIdGate.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title AegisVault - AI-Enhanced Guardian for Intelligent Staking
/// @notice Core vault that holds user funds, receives CRE reports, manages positions,
///         and coordinates with RiskRegistry, StrategyRouter, and WorldIdGate.
/// @dev Inherits ReceiverTemplate for CRE report processing. Uses virtual shares to
///      prevent first-depositor inflation attacks. Implements Ownable2Step pattern
///      manually (ReceiverTemplate uses Ownable, we override transferOwnership).
///      NEVER uses address(this).balance for share math - internal accounting only.
contract AegisVault is ReceiverTemplate, IAegisVault, ReentrancyGuard, Pausable {
    // ================================================================
    //                          CONSTANTS
    // ================================================================

    /// @notice Virtual shares offset to prevent first-depositor inflation attack (CRITICAL-001)
    uint256 public constant VIRTUAL_SHARES = 1e6;

    /// @notice Virtual assets offset to prevent first-depositor inflation attack (CRITICAL-001)
    uint256 public constant VIRTUAL_ASSETS = 1e6;

    /// @notice Default minimum deposit (0.001 ETH) to prevent dust attacks
    uint256 public constant DEFAULT_MIN_DEPOSIT = 0.001 ether;

    /// @notice Default minimum hold period (1 hour) for MEV protection (HIGH-001)
    uint256 public constant DEFAULT_MIN_HOLD_PERIOD = 1 hours;

    /// @notice Default circuit breaker max duration (72 hours) auto-deactivation (HIGH-003)
    uint256 public constant DEFAULT_CB_MAX_DURATION = 72 hours;

    // ================================================================
    //                       STATE VARIABLES
    // ================================================================

    // --- Position tracking (shares-based with virtual offset) ---
    mapping(address => uint256) private _shares;
    mapping(address => uint256) private _depositTimestamp;
    mapping(address => uint256) private _depositAmount;
    uint256 private _totalShares;
    uint256 private _totalDeposits;     // Internal accounting - NEVER use address(this).balance
    uint256 private _totalAllocated;    // Amount sent to strategies

    // --- Vault state ---
    bool private _circuitBreakerActive;
    uint256 private _circuitBreakerActivatedAt;
    uint256 private _circuitBreakerMaxDuration;
    bool private _initialSetupComplete;
    uint256 private _minDeposit;
    uint256 private _minHoldPeriod;

    // --- External contracts ---
    IRiskRegistry private _riskRegistry;
    IStrategyRouter private _strategyRouter;
    IWorldIdGate private _worldIdGate;

    // --- CRE report tracking ---
    mapping(bytes32 => bool) private _processedReports;
    mapping(bytes32 => bytes1) private _workflowToPrefix;  // workflowId => allowed prefix byte

    // --- Ownable2Step pattern (manual, since ReceiverTemplate uses Ownable) ---
    address private _pendingOwner;

    // --- Cross-chain allocation tracking ---
    mapping(uint64 => uint256) private _chainAllocations;

    // --- Temporary storage for workflow ID during report processing ---
    bytes32 private _currentWorkflowId;

    // ================================================================
    //                     ADDITIONAL ERRORS
    // ================================================================

    error ReportAlreadyProcessed(bytes32 reportKey);
    error WorkflowPrefixMismatch(bytes32 workflowId, bytes1 expected, bytes1 received);
    error NotPendingOwner(address caller);

    // ================================================================
    //                     ADDITIONAL EVENTS
    // ================================================================

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event YieldReportReceived(bytes32 indexed reportKey, bytes data);
    event RiskReportReceived(bytes32 indexed reportKey, bool shouldActivate, uint256 riskScore);
    event VaultOperationReceived(bytes32 indexed reportKey, bytes data);

    // ================================================================
    //                          MODIFIERS
    // ================================================================

    /// @notice Requires initial setup to be complete before user operations (HIGH-004)
    modifier onlyAfterSetup() {
        if (!_initialSetupComplete) revert SetupNotComplete();
        _;
    }

    /// @notice Requires circuit breaker to be inactive (HIGH-002: blocks BOTH deposits AND withdrawals)
    modifier whenCircuitBreakerInactive() {
        if (_isCircuitBreakerActive()) revert CircuitBreakerActive();
        _;
    }

    // ================================================================
    //                         CONSTRUCTOR
    // ================================================================

    /// @notice Deploy vault in paused state - must call completeInitialSetup() (HIGH-004)
    /// @param _forwarderAddress The Chainlink KeystoneForwarder address (cannot be zero)
    constructor(address _forwarderAddress) ReceiverTemplate(_forwarderAddress) {
        _minDeposit = DEFAULT_MIN_DEPOSIT;
        _minHoldPeriod = DEFAULT_MIN_HOLD_PERIOD;
        _circuitBreakerMaxDuration = DEFAULT_CB_MAX_DURATION;
        // _initialSetupComplete defaults to false - vault is locked until setup
    }

    // ================================================================
    //                       USER FUNCTIONS
    // ================================================================

    /// @inheritdoc IAegisVault
    function deposit(
        uint256 worldIdRoot,
        uint256 nullifierHash,
        uint256[8] calldata proof
    ) external payable override nonReentrant whenNotPaused onlyAfterSetup whenCircuitBreakerInactive {
        if (msg.value == 0) revert ZeroDeposit();
        if (msg.value < _minDeposit) revert BelowMinimumDeposit(msg.value, _minDeposit);

        // Verify World ID (if gate is configured)
        if (address(_worldIdGate) != address(0)) {
            _worldIdGate.verifyIdentity(msg.sender, worldIdRoot, nullifierHash, proof);
        }

        uint256 sharesToMint = _convertToShares(msg.value);

        _shares[msg.sender] += sharesToMint;
        _depositTimestamp[msg.sender] = block.timestamp;
        _depositAmount[msg.sender] += msg.value;
        _totalShares += sharesToMint;
        _totalDeposits += msg.value;

        emit Deposited(msg.sender, msg.value, sharesToMint);
    }

    /// @inheritdoc IAegisVault
    function withdraw(
        uint256 shares,
        uint256 worldIdRoot,
        uint256 nullifierHash,
        uint256[8] calldata proof
    ) external override nonReentrant whenNotPaused onlyAfterSetup whenCircuitBreakerInactive {
        if (shares == 0) revert ZeroDeposit();
        if (shares > _shares[msg.sender]) revert InsufficientShares(shares, _shares[msg.sender]);
        if (block.timestamp < _depositTimestamp[msg.sender] + _minHoldPeriod) {
            revert HoldPeriodNotElapsed(
                _depositTimestamp[msg.sender],
                _depositTimestamp[msg.sender] + _minHoldPeriod
            );
        }

        // Verify World ID (if gate is configured)
        if (address(_worldIdGate) != address(0)) {
            _worldIdGate.verifyIdentity(msg.sender, worldIdRoot, nullifierHash, proof);
        }

        uint256 assets = _convertToAssets(shares);

        // Effects before interactions (checks-effects-interactions)
        _shares[msg.sender] -= shares;
        _totalShares -= shares;
        if (assets > _totalDeposits) {
            _totalDeposits = 0;
        } else {
            _totalDeposits -= assets;
        }

        // Clear position if fully withdrawn
        if (_shares[msg.sender] == 0) {
            _depositTimestamp[msg.sender] = 0;
            _depositAmount[msg.sender] = 0;
        }

        emit Withdrawn(msg.sender, assets, shares);

        // Interaction: transfer ETH last (reentrancy guarded)
        (bool success,) = msg.sender.call{value: assets}("");
        if (!success) revert TransferFailed();
    }

    // ================================================================
    //                   CRE REPORT PROCESSING
    // ================================================================

    /// @notice Override onReport to capture workflowId for prefix binding validation
    /// @dev Stores workflowId in temporary state, then delegates to ReceiverTemplate
    ///      for standard forwarder/workflow validation, which calls _processReport
    function onReport(
        bytes calldata metadata,
        bytes calldata report
    ) public virtual override {
        // Capture workflowId before parent processing for prefix binding check
        if (metadata.length >= 62) {
            (_currentWorkflowId,,) = _decodeMetadata(metadata);
        }

        // Delegate to ReceiverTemplate for forwarder + workflow validation
        // ReceiverTemplate.onReport() will call _processReport(report)
        super.onReport(metadata, report);

        // Clean up temporary storage
        _currentWorkflowId = bytes32(0);
    }

    /// @inheritdoc ReceiverTemplate
    /// @dev Routes reports by prefix byte with workflow binding validation (CRITICAL-003)
    ///      and cross-chain replay protection (CRITICAL-004)
    function _processReport(bytes calldata report) internal override {
        if (report.length < 2) revert InvalidReportPrefix(bytes1(0));

        bytes1 prefix = bytes1(report[0]);
        bytes calldata reportData = report[1:];

        // Validate workflow-to-prefix binding (CRITICAL-003)
        if (_currentWorkflowId != bytes32(0)) {
            bytes1 allowedPrefix = _workflowToPrefix[_currentWorkflowId];
            if (allowedPrefix != bytes1(0) && allowedPrefix != prefix) {
                revert WorkflowPrefixMismatch(_currentWorkflowId, allowedPrefix, prefix);
            }
        }

        // Cross-chain replay prevention - include block.chainid in dedup key (CRITICAL-004)
        bytes32 reportKey = keccak256(abi.encodePacked(prefix, block.chainid, reportData));
        if (_processedReports[reportKey]) revert ReportAlreadyProcessed(reportKey);
        _processedReports[reportKey] = true;

        emit ReportProcessed(prefix, reportKey);

        if (prefix == 0x01) {
            _handleYieldReport(reportKey, reportData);
        } else if (prefix == 0x02) {
            _handleRiskReport(reportKey, reportData);
        } else if (prefix == 0x03) {
            _handleVaultOperation(reportKey, reportData);
        } else {
            revert InvalidReportPrefix(prefix);
        }
    }

    /// @notice Handle yield scanner report (prefix 0x01)
    /// @param reportKey The unique report key
    /// @param data The report data (after prefix byte)
    function _handleYieldReport(bytes32 reportKey, bytes calldata data) internal {
        // Will be fully connected to StrategyRouter in Phase 04
        emit YieldReportReceived(reportKey, data);
    }

    /// @notice Handle risk sentinel report (prefix 0x02)
    /// @param reportKey The unique report key
    /// @param data The report data: abi.encode(bool shouldActivateCircuitBreaker, uint256 riskScore)
    function _handleRiskReport(bytes32 reportKey, bytes calldata data) internal {
        (bool shouldActivate, uint256 riskScore) = abi.decode(data, (bool, uint256));

        emit RiskReportReceived(reportKey, shouldActivate, riskScore);

        if (shouldActivate && !_isCircuitBreakerActive()) {
            _circuitBreakerActive = true;
            _circuitBreakerActivatedAt = block.timestamp;
            emit CircuitBreakerActivated(block.timestamp, reportKey);
        }
    }

    /// @notice Handle vault manager operation report (prefix 0x03)
    /// @param reportKey The unique report key
    /// @param data The report data (after prefix byte)
    function _handleVaultOperation(bytes32 reportKey, bytes calldata data) internal {
        // Will be fully connected to StrategyRouter in Phase 04
        emit VaultOperationReceived(reportKey, data);
    }

    // ================================================================
    //                      CIRCUIT BREAKER
    // ================================================================

    /// @notice Activate circuit breaker (callable by RiskRegistry or owner)
    /// @param reportId The report ID that triggered activation
    function activateCircuitBreaker(bytes32 reportId) external {
        if (msg.sender != address(_riskRegistry) && msg.sender != owner()) {
            revert IAegisVault.CircuitBreakerActive(); // reusing error for unauthorized
        }
        if (!_isCircuitBreakerActive()) {
            _circuitBreakerActive = true;
            _circuitBreakerActivatedAt = block.timestamp;
            emit CircuitBreakerActivated(block.timestamp, reportId);
        }
    }

    /// @notice Deactivate circuit breaker (owner only)
    function deactivateCircuitBreaker() external onlyOwner {
        if (_circuitBreakerActive) {
            _circuitBreakerActive = false;
            emit CircuitBreakerDeactivated(block.timestamp);
        }
    }

    /// @inheritdoc IAegisVault
    /// @dev Includes auto-deactivation check (HIGH-003): returns false if max duration exceeded
    function isCircuitBreakerActive() external view override returns (bool) {
        return _isCircuitBreakerActive();
    }

    /// @notice Internal circuit breaker check with auto-deactivation (HIGH-003)
    function _isCircuitBreakerActive() internal view returns (bool) {
        if (!_circuitBreakerActive) return false;
        if (block.timestamp > _circuitBreakerActivatedAt + _circuitBreakerMaxDuration) {
            return false;
        }
        return true;
    }

    // ================================================================
    //                    ADMIN FUNCTIONS
    // ================================================================

    /// @notice Complete initial setup - enables user operations (HIGH-004)
    /// @dev Can only be called once. Must be called after all external contracts are set.
    function completeInitialSetup() external onlyOwner {
        if (_initialSetupComplete) revert SetupNotComplete(); // already done
        _initialSetupComplete = true;
        emit SetupCompleted(block.timestamp);
    }

    /// @notice Bind a workflow ID to its allowed report prefix byte (CRITICAL-003)
    /// @param workflowId The CRE workflow ID
    /// @param prefix The prefix byte this workflow is allowed to send
    function setWorkflowPrefix(bytes32 workflowId, bytes1 prefix) external onlyOwner {
        _workflowToPrefix[workflowId] = prefix;
        emit WorkflowPrefixBound(workflowId, prefix);
    }

    /// @notice Set the RiskRegistry contract address
    /// @param registry The new RiskRegistry address (MEDIUM-002: zero-address check)
    function setRiskRegistry(address registry) external onlyOwner {
        if (registry == address(0)) revert ZeroAddress();
        emit RiskRegistryUpdated(address(_riskRegistry), registry);
        _riskRegistry = IRiskRegistry(registry);
    }

    /// @notice Set the StrategyRouter contract address
    /// @param router The new StrategyRouter address (MEDIUM-002: zero-address check)
    function setStrategyRouter(address router) external onlyOwner {
        if (router == address(0)) revert ZeroAddress();
        emit StrategyRouterUpdated(address(_strategyRouter), router);
        _strategyRouter = IStrategyRouter(router);
    }

    /// @notice Set the WorldIdGate contract address
    /// @param gate The new WorldIdGate address (MEDIUM-002: zero-address check)
    function setWorldIdGate(address gate) external onlyOwner {
        if (gate == address(0)) revert ZeroAddress();
        emit WorldIdGateUpdated(address(_worldIdGate), gate);
        _worldIdGate = IWorldIdGate(gate);
    }

    /// @notice Update minimum deposit amount
    /// @param newMinDeposit New minimum deposit in wei
    function setMinDeposit(uint256 newMinDeposit) external onlyOwner {
        emit MinimumDepositUpdated(_minDeposit, newMinDeposit);
        _minDeposit = newMinDeposit;
    }

    /// @notice Update minimum hold period
    /// @param newMinHoldPeriod New minimum hold period in seconds
    function setMinHoldPeriod(uint256 newMinHoldPeriod) external onlyOwner {
        emit MinHoldPeriodUpdated(_minHoldPeriod, newMinHoldPeriod);
        _minHoldPeriod = newMinHoldPeriod;
    }

    /// @notice Override setForwarderAddress to prevent address(0) (HIGH-005)
    /// @param _forwarder New forwarder address (cannot be zero)
    function setForwarderAddress(address _forwarder) public override onlyOwner {
        if (_forwarder == address(0)) revert ForwarderCannotBeZero();
        super.setForwarderAddress(_forwarder);
    }

    // ================================================================
    //                   OWNABLE2STEP PATTERN
    // ================================================================

    /// @notice Override transferOwnership for 2-step pattern (VULN-002)
    /// @param newOwner The proposed new owner
    function transferOwnership(address newOwner) public override onlyOwner {
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner(), newOwner);
    }

    /// @notice Accept ownership transfer (2-step pattern)
    function acceptOwnership() public {
        if (msg.sender != _pendingOwner) revert NotPendingOwner(msg.sender);
        _transferOwnership(msg.sender);
        _pendingOwner = address(0);
    }

    /// @notice Get the pending owner address
    /// @return The pending owner address
    function pendingOwner() public view returns (address) {
        return _pendingOwner;
    }

    // ================================================================
    //                    PAUSABLE OVERRIDES
    // ================================================================

    /// @notice Pause the vault (owner only)
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the vault (owner only)
    function unpause() external onlyOwner {
        _unpause();
    }

    // ================================================================
    //                      VIEW FUNCTIONS
    // ================================================================

    /// @inheritdoc IAegisVault
    function getPosition(address user) external view override returns (Position memory) {
        return Position({
            shares: _shares[user],
            depositTimestamp: _depositTimestamp[user],
            depositAmount: _depositAmount[user]
        });
    }

    /// @inheritdoc IAegisVault
    /// @dev Returns internal accounting only - NEVER address(this).balance (CRITICAL-002)
    function getTotalAssets() external view override returns (uint256) {
        return _totalAssets();
    }

    /// @inheritdoc IAegisVault
    function convertToAssets(uint256 shares) external view override returns (uint256) {
        return _convertToAssets(shares);
    }

    /// @inheritdoc IAegisVault
    function convertToShares(uint256 assets) external view override returns (uint256) {
        return _convertToShares(assets);
    }

    /// @notice Get the total shares outstanding
    function totalShares() external view returns (uint256) {
        return _totalShares;
    }

    /// @notice Get the minimum deposit amount
    function minDeposit() external view returns (uint256) {
        return _minDeposit;
    }

    /// @notice Get the minimum hold period
    function minHoldPeriod() external view returns (uint256) {
        return _minHoldPeriod;
    }

    /// @notice Check if initial setup is complete
    function isSetupComplete() external view returns (bool) {
        return _initialSetupComplete;
    }

    /// @notice Get the RiskRegistry address
    function riskRegistry() external view returns (address) {
        return address(_riskRegistry);
    }

    /// @notice Get the StrategyRouter address
    function strategyRouter() external view returns (address) {
        return address(_strategyRouter);
    }

    /// @notice Get the WorldIdGate address
    function worldIdGate() external view returns (address) {
        return address(_worldIdGate);
    }

    /// @notice Check if a report has been processed
    function isReportProcessed(bytes32 reportKey) external view returns (bool) {
        return _processedReports[reportKey];
    }

    /// @notice Get the allowed prefix for a workflow
    function getWorkflowPrefix(bytes32 workflowId) external view returns (bytes1) {
        return _workflowToPrefix[workflowId];
    }

    // ================================================================
    //                    INTERNAL FUNCTIONS
    // ================================================================

    /// @notice Total assets available for withdrawal (internal accounting, CRITICAL-002)
    /// @dev NEVER uses address(this).balance
    function _totalAssets() internal view returns (uint256) {
        if (_totalDeposits <= _totalAllocated) return 0;
        return _totalDeposits - _totalAllocated;
    }

    /// @notice Convert assets to shares with virtual offset (CRITICAL-001)
    /// @dev Prevents first-depositor inflation attack via VIRTUAL_SHARES + VIRTUAL_ASSETS
    function _convertToShares(uint256 assets) internal view returns (uint256) {
        return Math.mulDiv(
            assets,
            _totalShares + VIRTUAL_SHARES,
            _totalAssets() + VIRTUAL_ASSETS
        );
    }

    /// @notice Convert shares to assets with virtual offset (CRITICAL-001)
    /// @dev Prevents first-depositor inflation attack via VIRTUAL_SHARES + VIRTUAL_ASSETS
    function _convertToAssets(uint256 shares) internal view returns (uint256) {
        return Math.mulDiv(
            shares,
            _totalAssets() + VIRTUAL_ASSETS,
            _totalShares + VIRTUAL_SHARES
        );
    }

    /// @notice Receive ETH (for CCIP refunds, etc.)
    receive() external payable {}
}
