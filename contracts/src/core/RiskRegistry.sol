// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IRiskRegistry} from "../interfaces/IRiskRegistry.sol";
import {RiskMath} from "../libraries/RiskMath.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title RiskRegistry - Risk Management Engine for AEGIS Protocol
/// @notice Manages per-protocol risk scores, circuit breaker with rate limiting (max 3/hr),
///         threshold-based safety checks, and auto-deactivation.
/// @dev Uses O(1) alert counter instead of unbounded arrays (MEDIUM-001).
///      Separates evaluateRisk (view) from recordRiskAssessment (state) (MEDIUM-002).
///      All thresholds have bounds to prevent untriggerable configs (HIGH-002).
contract RiskRegistry is IRiskRegistry, Ownable2Step, Pausable {
    // ================================================================
    //                          CONSTANTS
    // ================================================================

    /// @notice Maximum risk score in basis points (100.00%)
    uint256 public constant MAX_RISK_SCORE = 10_000;

    /// @notice Minimum allowed risk threshold (10.00%)
    uint256 public constant MIN_THRESHOLD = 1_000;

    /// @notice Maximum allowed risk threshold (95.00%)
    uint256 public constant MAX_THRESHOLD = 9_500;

    /// @notice Maximum circuit breaker activations per rate limit window (HIGH-001)
    uint256 public constant DEFAULT_MAX_ACTIVATIONS = 3;

    /// @notice Rate limit window duration (1 hour)
    uint256 public constant RATE_LIMIT_WINDOW = 1 hours;

    /// @notice Default auto-deactivation period (72 hours)
    uint256 public constant DEFAULT_AUTO_DEACTIVATION = 72 hours;

    /// @notice Default risk threshold (70.00% = 7000 bps)
    uint256 public constant DEFAULT_THRESHOLD = 7_000;

    // ================================================================
    //                       STATE VARIABLES
    // ================================================================

    // --- Risk assessments per protocol ---
    mapping(address => RiskAssessment) private _assessments;

    // --- Circuit breaker state ---
    bool private _cbActive;
    uint256 private _cbActivatedAt;
    uint256 private _cbActivationCount;      // Activations in current window
    uint256 private _cbWindowStart;           // Rate limit window start
    bytes32 private _cbLastReportId;
    uint256 private _autoDeactivationPeriod;
    uint256 private _maxActivationsPerWindow;

    // --- Risk threshold ---
    uint256 private _riskThreshold;

    // --- Alert counter (O(1) instead of unbounded array, MEDIUM-001) ---
    mapping(address => uint256) private _alertCounts;
    uint256 private _totalAlerts;

    // --- Authorization ---
    mapping(address => bool) private _authorizedVaults;
    mapping(address => bool) private _authorizedSentinels;

    // ================================================================
    //                     ADDITIONAL EVENTS
    // ================================================================

    event SentinelAuthorized(address indexed sentinel, bool authorized);
    event RiskAlertCreated(
        address indexed protocol,
        uint256 score,
        uint256 threshold,
        uint256 alertNumber,
        uint256 timestamp
    );

    // ================================================================
    //                         CONSTRUCTOR
    // ================================================================

    /// @notice Deploy RiskRegistry with default configuration
    constructor() Ownable(msg.sender) {
        _riskThreshold = DEFAULT_THRESHOLD;
        _autoDeactivationPeriod = DEFAULT_AUTO_DEACTIVATION;
        _maxActivationsPerWindow = DEFAULT_MAX_ACTIVATIONS;
    }

    // ================================================================
    //                      RISK MANAGEMENT
    // ================================================================

    /// @notice Evaluate risk score from weighted factors (pure view, no state change, MEDIUM-002)
    /// @param factors Array of risk factor scores (each 0-10000 bps)
    /// @param weights Array of weights for each factor
    /// @return score Weighted average risk score
    /// @return shouldTriggerBreaker Whether the score exceeds the threshold
    function evaluateRisk(
        uint256[] memory factors,
        uint256[] memory weights
    ) external view returns (uint256 score, bool shouldTriggerBreaker) {
        score = RiskMath.calculateRiskScore(factors, weights);
        shouldTriggerBreaker = score >= _riskThreshold;
    }

    /// @inheritdoc IRiskRegistry
    function updateRiskScore(
        address protocol,
        uint256 score,
        bytes32 reportId
    ) external override whenNotPaused {
        if (!_authorizedSentinels[msg.sender] && !_authorizedVaults[msg.sender] && msg.sender != owner()) {
            revert CallerNotAuthorized(msg.sender);
        }
        if (!_assessments[protocol].isMonitored) revert ProtocolNotMonitored(protocol);
        if (score > MAX_RISK_SCORE) revert InvalidRiskScore(score);

        uint256 oldScore = _assessments[protocol].score;
        _assessments[protocol].score = score;
        _assessments[protocol].lastUpdated = block.timestamp;

        emit RiskScoreUpdated(protocol, oldScore, score, reportId);

        // Auto-create alert if score exceeds threshold
        if (score >= _riskThreshold) {
            _alertCounts[protocol]++;
            _totalAlerts++;
            emit RiskAlertCreated(protocol, score, _riskThreshold, _alertCounts[protocol], block.timestamp);
        }
    }

    /// @inheritdoc IRiskRegistry
    function getRiskAssessment(address protocol) external view override returns (RiskAssessment memory) {
        return _assessments[protocol];
    }

    /// @inheritdoc IRiskRegistry
    function isProtocolSafe(address protocol) external view override returns (bool) {
        if (!_assessments[protocol].isMonitored) return false;
        return _assessments[protocol].score < _riskThreshold;
    }

    // ================================================================
    //                      CIRCUIT BREAKER
    // ================================================================

    /// @inheritdoc IRiskRegistry
    /// @dev Rate-limited: max activations per window (HIGH-001)
    function activateCircuitBreaker(bytes32 reportId) external override whenNotPaused {
        if (!_authorizedSentinels[msg.sender] && !_authorizedVaults[msg.sender] && msg.sender != owner()) {
            revert CallerNotAuthorized(msg.sender);
        }
        if (_isCircuitBreakerActive()) revert CircuitBreakerAlreadyActive();

        // Rate limiting (HIGH-001): reset window if expired, then check count
        if (block.timestamp > _cbWindowStart + RATE_LIMIT_WINDOW) {
            _cbActivationCount = 0;
            _cbWindowStart = block.timestamp;
        }
        if (_cbActivationCount >= _maxActivationsPerWindow) {
            revert CircuitBreakerRateLimited(_cbActivationCount, _maxActivationsPerWindow);
        }
        _cbActivationCount++;

        _cbActive = true;
        _cbActivatedAt = block.timestamp;
        _cbLastReportId = reportId;

        emit CircuitBreakerActivated(msg.sender, reportId, block.timestamp);
    }

    /// @inheritdoc IRiskRegistry
    function deactivateCircuitBreaker() external override onlyOwner {
        if (!_cbActive) revert CircuitBreakerNotActive();

        _cbActive = false;
        emit CircuitBreakerDeactivated(msg.sender, block.timestamp);
    }

    /// @inheritdoc IRiskRegistry
    function getCircuitBreakerState() external view override returns (CircuitBreakerState memory) {
        return CircuitBreakerState({
            isActive: _isCircuitBreakerActive(),
            activatedAt: _cbActivatedAt,
            activationCount: _cbActivationCount,
            windowStart: _cbWindowStart,
            lastTriggerReportId: _cbLastReportId
        });
    }

    /// @inheritdoc IRiskRegistry
    /// @dev Includes auto-deactivation check
    function isCircuitBreakerActive() external view override returns (bool) {
        return _isCircuitBreakerActive();
    }

    /// @notice Internal circuit breaker check with auto-deactivation
    function _isCircuitBreakerActive() internal view returns (bool) {
        if (!_cbActive) return false;
        if (block.timestamp > _cbActivatedAt + _autoDeactivationPeriod) return false;
        return true;
    }

    // ================================================================
    //                      CONFIGURATION
    // ================================================================

    /// @inheritdoc IRiskRegistry
    /// @dev Enforces bounds: MIN_THRESHOLD <= threshold <= MAX_THRESHOLD (HIGH-002)
    function setThreshold(uint256 threshold) external override onlyOwner {
        if (threshold < MIN_THRESHOLD || threshold > MAX_THRESHOLD) {
            revert ThresholdOutOfBounds(threshold, MIN_THRESHOLD, MAX_THRESHOLD);
        }
        emit ThresholdUpdated(_riskThreshold, threshold);
        _riskThreshold = threshold;
    }

    /// @inheritdoc IRiskRegistry
    function addProtocol(address protocol, string calldata name) external override onlyOwner {
        if (protocol == address(0)) revert ZeroAddress();
        _assessments[protocol] = RiskAssessment({
            score: 0,
            lastUpdated: block.timestamp,
            isMonitored: true
        });
        emit ProtocolAdded(protocol, name);
    }

    /// @inheritdoc IRiskRegistry
    function removeProtocol(address protocol) external override onlyOwner {
        if (!_assessments[protocol].isMonitored) revert ProtocolNotMonitored(protocol);
        _assessments[protocol].isMonitored = false;
        emit ProtocolRemoved(protocol);
    }

    /// @notice Set max activations per rate limit window
    /// @param maxActivations New max activations (must be >= 1)
    function setMaxActivationsPerWindow(uint256 maxActivations) external onlyOwner {
        if (maxActivations == 0) revert ThresholdOutOfBounds(maxActivations, 1, type(uint256).max);
        emit MaxActivationsPerWindowUpdated(_maxActivationsPerWindow, maxActivations);
        _maxActivationsPerWindow = maxActivations;
    }

    /// @notice Set the auto-deactivation period
    /// @param period New period in seconds (must be >= 1 hour)
    function setAutoDeactivationPeriod(uint256 period) external onlyOwner {
        if (period < 1 hours) revert ThresholdOutOfBounds(period, 1 hours, type(uint256).max);
        emit AutoDeactivationPeriodUpdated(_autoDeactivationPeriod, period);
        _autoDeactivationPeriod = period;
    }

    // ================================================================
    //                      AUTHORIZATION
    // ================================================================

    /// @notice Register a vault as authorized caller
    /// @param vault The vault address
    function registerVault(address vault) external onlyOwner {
        if (vault == address(0)) revert ZeroAddress();
        _authorizedVaults[vault] = true;
        emit VaultRegistered(vault);
    }

    /// @notice Remove a vault from authorized callers
    /// @param vault The vault address
    function removeVault(address vault) external onlyOwner {
        _authorizedVaults[vault] = false;
    }

    /// @notice Authorize a sentinel (CRE workflow proxy) to update risk scores
    /// @param sentinel The sentinel address
    /// @param authorized Whether to authorize or deauthorize
    function setSentinelAuthorization(address sentinel, bool authorized) external onlyOwner {
        if (sentinel == address(0)) revert ZeroAddress();
        _authorizedSentinels[sentinel] = authorized;
        emit SentinelAuthorized(sentinel, authorized);
    }

    // ================================================================
    //                      PAUSABLE
    // ================================================================

    /// @notice Pause the risk registry (MEDIUM-003: independent pause)
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the risk registry
    function unpause() external onlyOwner {
        _unpause();
    }

    // ================================================================
    //                      VIEW FUNCTIONS
    // ================================================================

    /// @notice Get the current risk threshold
    function riskThreshold() external view returns (uint256) {
        return _riskThreshold;
    }

    /// @notice Get the alert count for a protocol
    function getAlertCount(address protocol) external view returns (uint256) {
        return _alertCounts[protocol];
    }

    /// @notice Get the total alert count across all protocols
    function totalAlerts() external view returns (uint256) {
        return _totalAlerts;
    }

    /// @notice Check if an address is an authorized vault
    function isAuthorizedVault(address vault) external view returns (bool) {
        return _authorizedVaults[vault];
    }

    /// @notice Check if an address is an authorized sentinel
    function isAuthorizedSentinel(address sentinel) external view returns (bool) {
        return _authorizedSentinels[sentinel];
    }

    /// @notice Get current max activations per window
    function maxActivationsPerWindow() external view returns (uint256) {
        return _maxActivationsPerWindow;
    }

    /// @notice Get current auto-deactivation period
    function autoDeactivationPeriod() external view returns (uint256) {
        return _autoDeactivationPeriod;
    }
}
