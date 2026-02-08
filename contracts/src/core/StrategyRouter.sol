// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IStrategyRouter} from "../interfaces/IStrategyRouter.sol";
import {IRiskRegistry} from "../interfaces/IRiskRegistry.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title StrategyRouter - Cross-Chain Capital Routing for AEGIS Protocol
/// @notice Routes capital across chains via CCIP, enforces cumulative transfer limits,
///         manages 1inch swap selector whitelist, and tracks CCIP message nonces.
/// @dev Implements IAny2EVMMessageReceiver directly (avoids CCIPReceiver vendored OZ conflict).
///      All cross-chain messages include monotonic nonce for replay prevention.
///      Cumulative transfer limits enforce max % of TVL per time window.
contract StrategyRouter is
    IStrategyRouter,
    IAny2EVMMessageReceiver,
    IERC165,
    Ownable2Step,
    ReentrancyGuard,
    Pausable
{
    // ================================================================
    //                          CONSTANTS
    // ================================================================

    /// @notice Maximum basis points (100%)
    uint256 public constant MAX_BPS = 10_000;

    /// @notice Default cumulative transfer window (24 hours)
    uint256 public constant DEFAULT_TRANSFER_WINDOW = 24 hours;

    /// @notice Default max cumulative transfer (20% of TVL per window)
    uint256 public constant DEFAULT_MAX_CUMULATIVE_BPS = 2_000;

    /// @notice CCIP extra args gas limit for destination execution
    uint256 public constant CCIP_GAS_LIMIT = 200_000;

    // ================================================================
    //                       STATE VARIABLES
    // ================================================================

    // --- CCIP ---
    IRouterClient public ccipRouter;
    mapping(uint64 => bool) private _allowedChains;
    mapping(uint64 => address) private _chainReceivers; // chainSelector => authorized sender/receiver

    // --- Strategy ---
    mapping(uint64 => uint256) private _targetAllocations; // chainSelector => bps
    uint64[] private _allocatedChains; // Track which chains have allocations

    // --- Cumulative transfer limits (HIGH-001) ---
    uint256 private _transferWindowDuration;
    uint256 private _maxCumulativeTransferBps;
    mapping(uint256 => uint256) private _windowTransfers; // windowId => amount transferred
    uint256 private _totalVaultValue; // Updated by vault

    // --- CCIP nonce (HIGH-002) ---
    uint256 private _messageNonce;
    mapping(uint64 => uint256) private _expectedNonce; // sourceChain => expected nonce

    // --- Pending transfers (HIGH-003) ---
    struct PendingTransfer {
        uint64 destChainSelector;
        uint256 amount;
        uint256 timestamp;
        bool completed;
        bool failed;
    }
    mapping(bytes32 => PendingTransfer) private _pendingTransfers;

    // --- Authorization ---
    address private _aegisVault;
    IRiskRegistry private _riskRegistry;

    // --- 1inch integration (HIGH-004) ---
    address private _oneInchRouter;
    mapping(bytes4 => bool) private _allowed1inchSelectors;

    // ================================================================
    //                     ADDITIONAL ERRORS
    // ================================================================

    error AllocationsExceedMax(uint256 total);
    error ArrayLengthMismatch();
    error InvalidRouter(address router);

    // ================================================================
    //                     ADDITIONAL EVENTS
    // ================================================================

    event EmergencyWithdrawInitiated(uint64 indexed chainSelector, address indexed caller, uint256 timestamp);
    event PendingTransferCreated(bytes32 indexed messageId, uint64 indexed destChainSelector, uint256 amount);
    event PendingTransferCompleted(bytes32 indexed messageId);
    event PendingTransferFailed(bytes32 indexed messageId);
    event TotalVaultValueUpdated(uint256 oldValue, uint256 newValue);
    event OneInchRouterUpdated(address indexed oldRouter, address indexed newRouter);
    event TargetAllocationsUpdated(uint64[] chains, uint256[] allocations);
    event CCIPRouterUpdated(address indexed oldRouter, address indexed newRouter);

    // ================================================================
    //                          MODIFIERS
    // ================================================================

    modifier onlyRouter() {
        if (msg.sender != address(ccipRouter)) revert InvalidRouter(msg.sender);
        _;
    }

    modifier onlyVaultOrOwner() {
        if (msg.sender != _aegisVault && msg.sender != owner()) {
            revert CallerNotAuthorized(msg.sender);
        }
        _;
    }

    // ================================================================
    //                         CONSTRUCTOR
    // ================================================================

    /// @param _router The CCIP router address
    constructor(address _router) Ownable(msg.sender) {
        if (_router == address(0)) revert ZeroAddress();
        ccipRouter = IRouterClient(_router);
        _transferWindowDuration = DEFAULT_TRANSFER_WINDOW;
        _maxCumulativeTransferBps = DEFAULT_MAX_CUMULATIVE_BPS;
    }

    // ================================================================
    //                    STRATEGY EXECUTION
    // ================================================================

    /// @inheritdoc IStrategyRouter
    function executeStrategy(
        StrategyParams calldata params,
        bytes32 reportId
    ) external override nonReentrant whenNotPaused onlyVaultOrOwner {
        if (params.amount == 0) revert ZeroAmount();
        if (!_allowedChains[params.destinationChainSelector]) {
            revert InvalidChainSelector(params.destinationChainSelector);
        }

        // Check circuit breaker via risk registry
        if (address(_riskRegistry) != address(0) && _riskRegistry.isCircuitBreakerActive()) {
            revert CircuitBreakerActive();
        }

        emit StrategyExecuted(reportId, params.targetProtocol, params.actionType, params.amount);
    }

    /// @inheritdoc IStrategyRouter
    function bridgeAssets(
        uint64 destinationChainSelector,
        address receiver,
        uint256 amount
    ) external payable override nonReentrant whenNotPaused onlyVaultOrOwner returns (bytes32 ccipMessageId) {
        if (amount == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        if (!_allowedChains[destinationChainSelector]) {
            revert InvalidChainSelector(destinationChainSelector);
        }

        // Check cumulative transfer limit (HIGH-001)
        _checkCumulativeLimit(amount);

        // Increment nonce (HIGH-002)
        uint256 nonce = ++_messageNonce;

        // Build CCIP message payload with nonce + source chain
        bytes memory payload = abi.encode(
            uint8(0x01), // messageType: deposit
            nonce,
            uint64(block.chainid),
            receiver,
            amount,
            bytes("")
        );

        // Build CCIP message
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(_chainReceivers[destinationChainSelector]),
            data: payload,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            feeToken: address(0), // Pay in native
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: CCIP_GAS_LIMIT}))
        });

        // Get fee
        uint256 fee = ccipRouter.getFee(destinationChainSelector, message);
        if (msg.value < fee) revert InsufficientFee(fee, msg.value);

        // Send CCIP message
        ccipMessageId = ccipRouter.ccipSend{value: fee}(destinationChainSelector, message);

        // Track pending transfer (HIGH-003)
        _pendingTransfers[ccipMessageId] = PendingTransfer({
            destChainSelector: destinationChainSelector,
            amount: amount,
            timestamp: block.timestamp,
            completed: false,
            failed: false
        });

        emit CrossChainMessageSent(ccipMessageId, destinationChainSelector, receiver, amount, nonce);
        emit PendingTransferCreated(ccipMessageId, destinationChainSelector, amount);
    }

    // ================================================================
    //                    CCIP RECEIVE
    // ================================================================

    /// @notice Receive CCIP messages (called by CCIP router only)
    /// @dev Validates source chain + sender (CRITICAL-001), checks nonce (MEDIUM-001)
    function ccipReceive(
        Client.Any2EVMMessage calldata message
    ) external override onlyRouter {
        // Validate source chain (CRITICAL-001)
        if (!_allowedChains[message.sourceChainSelector]) {
            revert InvalidChainSelector(message.sourceChainSelector);
        }

        // Validate sender (CRITICAL-001)
        address sender = abi.decode(message.sender, (address));
        address expectedSender = _chainReceivers[message.sourceChainSelector];
        if (sender != expectedSender) {
            revert InvalidSourceSender(sender, expectedSender);
        }

        // Decode nonce from payload and validate (MEDIUM-001)
        (, uint256 nonce,,,,) = abi.decode(
            message.data,
            (uint8, uint256, uint64, address, uint256, bytes)
        );

        // Nonce must be exactly expectedNonce + 1 (sequential ordering)
        uint256 expected = _expectedNonce[message.sourceChainSelector] + 1;
        if (nonce != expected) {
            revert NonceAlreadyUsed(nonce);
        }
        _expectedNonce[message.sourceChainSelector] = nonce;

        emit CrossChainMessageReceived(
            message.messageId,
            message.sourceChainSelector,
            sender,
            nonce
        );
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IAny2EVMMessageReceiver).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    // ================================================================
    //                    EMERGENCY FUNCTIONS
    // ================================================================

    /// @notice Emergency withdraw all funds from a chain (CRITICAL-002: owner only, with event)
    /// @param chainSelector The chain to withdraw from
    function emergencyWithdrawAll(uint64 chainSelector) external onlyOwner whenNotPaused {
        if (!_allowedChains[chainSelector]) revert InvalidChainSelector(chainSelector);

        emit EmergencyWithdrawInitiated(chainSelector, msg.sender, block.timestamp);

        uint256 nonce = ++_messageNonce;

        bytes memory payload = abi.encode(
            uint8(0x03), // messageType: emergency
            nonce,
            uint64(block.chainid),
            address(0),
            uint256(0),
            bytes("")
        );

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(_chainReceivers[chainSelector]),
            data: payload,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            feeToken: address(0),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: CCIP_GAS_LIMIT}))
        });

        uint256 fee = ccipRouter.getFee(chainSelector, message);
        ccipRouter.ccipSend{value: fee}(chainSelector, message);
    }

    /// @notice Mark a pending transfer as failed (owner can then reclaim)
    /// @param messageId The CCIP message ID
    function markTransferFailed(bytes32 messageId) external onlyOwner {
        PendingTransfer storage pt = _pendingTransfers[messageId];
        if (pt.timestamp == 0) revert MessageAlreadyProcessed(messageId);
        if (pt.completed || pt.failed) revert MessageAlreadyProcessed(messageId);

        pt.failed = true;
        emit PendingTransferFailed(messageId);
    }

    // ================================================================
    //                    ADMIN FUNCTIONS
    // ================================================================

    /// @notice Set the CCIP router address
    function setCCIPRouter(address router) external onlyOwner {
        if (router == address(0)) revert ZeroAddress();
        emit CCIPRouterUpdated(address(ccipRouter), router);
        ccipRouter = IRouterClient(router);
    }

    /// @notice Set the AegisVault address
    function setVault(address vault) external onlyOwner {
        if (vault == address(0)) revert ZeroAddress();
        emit VaultUpdated(_aegisVault, vault);
        _aegisVault = vault;
    }

    /// @notice Set the RiskRegistry address
    function setRiskRegistry(address registry) external onlyOwner {
        if (registry == address(0)) revert ZeroAddress();
        emit RiskRegistryUpdated(address(_riskRegistry), registry);
        _riskRegistry = IRiskRegistry(registry);
    }

    /// @notice Allow or disallow a chain for CCIP messaging
    function setAllowedChain(uint64 chainSelector, bool allowed) external onlyOwner {
        _allowedChains[chainSelector] = allowed;
        emit AllowedChainUpdated(chainSelector, allowed);
    }

    /// @notice Set the authorized sender/receiver for a chain
    function setChainReceiver(uint64 chainSelector, address receiver) external onlyOwner {
        if (receiver == address(0)) revert ZeroAddress();
        _chainReceivers[chainSelector] = receiver;
        emit AllowedSenderUpdated(chainSelector, receiver, true);
    }

    /// @notice Set target allocations (MEDIUM-002: validates sum <= 100%)
    function setTargetAllocations(
        uint64[] calldata chains,
        uint256[] calldata allocBps
    ) external onlyOwner {
        if (chains.length != allocBps.length) revert ArrayLengthMismatch();

        // Clear old allocations
        for (uint256 i; i < _allocatedChains.length; ++i) {
            _targetAllocations[_allocatedChains[i]] = 0;
        }
        delete _allocatedChains;

        uint256 totalBps;
        for (uint256 i; i < chains.length; ++i) {
            _targetAllocations[chains[i]] = allocBps[i];
            _allocatedChains.push(chains[i]);
            totalBps += allocBps[i];
        }

        if (totalBps > MAX_BPS) revert AllocationsExceedMax(totalBps);

        emit TargetAllocationsUpdated(chains, allocBps);
    }

    /// @notice Update the cumulative transfer limit
    function setMaxCumulativeTransferBps(uint256 maxBps) external onlyOwner {
        if (maxBps > MAX_BPS) revert AllocationsExceedMax(maxBps);
        emit TransferLimitUpdated(_maxCumulativeTransferBps, maxBps);
        _maxCumulativeTransferBps = maxBps;
    }

    /// @notice Update the transfer window duration
    function setTransferWindowDuration(uint256 duration) external onlyOwner {
        if (duration == 0) revert ZeroAmount();
        emit TransferWindowDurationUpdated(_transferWindowDuration, duration);
        _transferWindowDuration = duration;
    }

    /// @notice Update total vault value (called by vault for cumulative limit calculations)
    function updateTotalVaultValue(uint256 value) external onlyVaultOrOwner {
        emit TotalVaultValueUpdated(_totalVaultValue, value);
        _totalVaultValue = value;
    }

    /// @notice Set the 1inch router address
    function setOneInchRouter(address router) external onlyOwner {
        emit OneInchRouterUpdated(_oneInchRouter, router);
        _oneInchRouter = router;
    }

    /// @notice Whitelist or remove a 1inch function selector (HIGH-004)
    function setSwapSelectorWhitelist(bytes4 selector, bool allowed) external onlyOwner {
        _allowed1inchSelectors[selector] = allowed;
        emit SwapSelectorWhitelisted(selector, allowed);
    }

    // ================================================================
    //                    PAUSABLE
    // ================================================================

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ================================================================
    //                    VIEW FUNCTIONS
    // ================================================================

    /// @inheritdoc IStrategyRouter
    function getRemainingTransferBudget() external view override returns (uint256 remaining) {
        if (_totalVaultValue == 0) return 0;
        uint256 windowId = block.timestamp / _transferWindowDuration;
        uint256 maxTransfer = (_totalVaultValue * _maxCumulativeTransferBps) / MAX_BPS;
        uint256 used = _windowTransfers[windowId];
        if (used >= maxTransfer) return 0;
        remaining = maxTransfer - used;
    }

    /// @inheritdoc IStrategyRouter
    function isChainAllowed(uint64 chainSelector) external view override returns (bool) {
        return _allowedChains[chainSelector];
    }

    /// @inheritdoc IStrategyRouter
    function getCurrentNonce() external view override returns (uint256) {
        return _messageNonce;
    }

    /// @notice Get the vault address
    function vault() external view returns (address) { return _aegisVault; }

    /// @notice Get pending transfer details
    function getPendingTransfer(bytes32 messageId) external view returns (PendingTransfer memory) {
        return _pendingTransfers[messageId];
    }

    /// @notice Get target allocation for a chain
    function getTargetAllocation(uint64 chainSelector) external view returns (uint256) {
        return _targetAllocations[chainSelector];
    }

    /// @notice Check if a 1inch selector is whitelisted
    function isSwapSelectorAllowed(bytes4 selector) external view returns (bool) {
        return _allowed1inchSelectors[selector];
    }

    /// @notice Get chain receiver address
    function getChainReceiver(uint64 chainSelector) external view returns (address) {
        return _chainReceivers[chainSelector];
    }

    // ================================================================
    //                    INTERNAL FUNCTIONS
    // ================================================================

    /// @notice Check cumulative transfer limit (HIGH-001)
    function _checkCumulativeLimit(uint256 amount) internal {
        if (_totalVaultValue == 0) return; // No limit if vault value not set

        uint256 windowId = block.timestamp / _transferWindowDuration;
        _windowTransfers[windowId] += amount;

        uint256 maxTransfer = (_totalVaultValue * _maxCumulativeTransferBps) / MAX_BPS;
        if (_windowTransfers[windowId] > maxTransfer) {
            uint256 remaining = maxTransfer > (_windowTransfers[windowId] - amount)
                ? maxTransfer - (_windowTransfers[windowId] - amount)
                : 0;
            revert TransferLimitExceeded(amount, remaining);
        }
    }

    /// @notice Accept ETH for CCIP fees and bridging
    receive() external payable {}
}
