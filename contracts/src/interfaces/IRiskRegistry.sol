// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IRiskRegistry - Interface for the AEGIS Protocol risk engine
/// @notice Manages risk scores per protocol, circuit breaker activation with rate limiting,
///         and threshold-based safety checks
interface IRiskRegistry {
    // ================================================================
    //                           STRUCTS
    // ================================================================

    /// @notice Risk assessment for a monitored protocol
    struct RiskAssessment {
        uint256 score;          // 0-10000 (basis points, 100.00%)
        uint256 lastUpdated;    // Timestamp of last update
        bool isMonitored;       // Whether this protocol is actively monitored
    }

    /// @notice Circuit breaker state
    struct CircuitBreakerState {
        bool isActive;
        uint256 activatedAt;
        uint256 activationCount;     // Activations in current window
        uint256 windowStart;         // Start of rate limit window
        bytes32 lastTriggerReportId; // Report ID that triggered activation
    }

    // ================================================================
    //                           ERRORS
    // ================================================================

    error ZeroAddress();
    error ProtocolNotMonitored(address protocol);
    error InvalidRiskScore(uint256 score);
    error CircuitBreakerAlreadyActive();
    error CircuitBreakerNotActive();
    error CircuitBreakerRateLimited(uint256 activationsInWindow, uint256 maxPerWindow);
    error ThresholdOutOfBounds(uint256 threshold, uint256 min, uint256 max);
    error CallerNotAuthorized(address caller);

    // ================================================================
    //                           EVENTS
    // ================================================================

    event RiskScoreUpdated(
        address indexed protocol,
        uint256 oldScore,
        uint256 newScore,
        bytes32 indexed reportId
    );
    event ProtocolAdded(address indexed protocol, string name);
    event ProtocolRemoved(address indexed protocol);
    event CircuitBreakerActivated(
        address indexed trigger,
        bytes32 indexed reportId,
        uint256 timestamp
    );
    event CircuitBreakerDeactivated(address indexed deactivator, uint256 timestamp);
    event CircuitBreakerAutoDeactivated(uint256 timestamp, uint256 activeDuration);
    event ThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event MaxActivationsPerWindowUpdated(uint256 oldMax, uint256 newMax);
    event AutoDeactivationPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event VaultRegistered(address indexed vault);

    // ================================================================
    //                      RISK MANAGEMENT
    // ================================================================

    /// @notice Update the risk score for a monitored protocol
    /// @param protocol The protocol address
    /// @param score New risk score (0-10000 basis points)
    /// @param reportId The CRE report ID that triggered this update
    function updateRiskScore(address protocol, uint256 score, bytes32 reportId) external;

    /// @notice Get the current risk score for a protocol
    /// @param protocol The protocol address
    /// @return The current RiskAssessment
    function getRiskAssessment(address protocol) external view returns (RiskAssessment memory);

    /// @notice Check if a protocol's risk score is below the safety threshold
    /// @param protocol The protocol address
    /// @return True if the protocol is considered safe
    function isProtocolSafe(address protocol) external view returns (bool);

    // ================================================================
    //                      CIRCUIT BREAKER
    // ================================================================

    /// @notice Activate the circuit breaker (rate-limited: max 3 per hour)
    /// @param reportId The CRE report ID triggering activation
    function activateCircuitBreaker(bytes32 reportId) external;

    /// @notice Deactivate the circuit breaker (owner only)
    function deactivateCircuitBreaker() external;

    /// @notice Get the current circuit breaker state
    /// @return The CircuitBreakerState struct
    function getCircuitBreakerState() external view returns (CircuitBreakerState memory);

    /// @notice Check if the circuit breaker is active (includes auto-deactivation check)
    /// @return True if active and within auto-deactivation window
    function isCircuitBreakerActive() external view returns (bool);

    // ================================================================
    //                      CONFIGURATION
    // ================================================================

    /// @notice Set the risk threshold (score above which protocols are unsafe)
    /// @param threshold New threshold in basis points (0-10000)
    function setThreshold(uint256 threshold) external;

    /// @notice Add a protocol to the monitored set
    /// @param protocol The protocol address
    /// @param name Human-readable protocol name
    function addProtocol(address protocol, string calldata name) external;

    /// @notice Remove a protocol from monitoring
    /// @param protocol The protocol address
    function removeProtocol(address protocol) external;
}
