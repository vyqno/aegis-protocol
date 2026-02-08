// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IAegisVault - Interface for the AEGIS Protocol main vault
/// @notice Defines the external interface for deposit/withdraw with World ID verification,
///         circuit breaker state, and CRE report processing
interface IAegisVault {
    // ================================================================
    //                           STRUCTS
    // ================================================================

    /// @notice User position in the vault
    struct Position {
        uint256 shares;
        uint256 depositTimestamp;
        uint256 depositAmount;
    }

    // ================================================================
    //                           ERRORS
    // ================================================================

    error ZeroDeposit();
    error BelowMinimumDeposit(uint256 amount, uint256 minimum);
    error CircuitBreakerActive();
    error InsufficientShares(uint256 requested, uint256 available);
    error HoldPeriodNotElapsed(uint256 depositTime, uint256 minHoldUntil);
    error SetupNotComplete();
    error ZeroAddress();
    error ForwarderCannotBeZero();
    error InvalidReportPrefix(bytes1 prefix);
    error TransferFailed();

    // ================================================================
    //                           EVENTS
    // ================================================================

    event Deposited(address indexed user, uint256 assets, uint256 shares);
    event Withdrawn(address indexed user, uint256 assets, uint256 shares);
    event CircuitBreakerActivated(uint256 timestamp, bytes32 indexed reportId);
    event CircuitBreakerDeactivated(uint256 timestamp);
    event CircuitBreakerAutoDeactivated(uint256 timestamp, uint256 activeDuration);
    event SetupCompleted(uint256 timestamp);
    event ReportProcessed(bytes1 indexed prefix, bytes32 indexed reportId);
    event RiskRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    event StrategyRouterUpdated(address indexed oldRouter, address indexed newRouter);
    event WorldIdGateUpdated(address indexed oldGate, address indexed newGate);
    event MinimumDepositUpdated(uint256 oldMinimum, uint256 newMinimum);
    event MinHoldPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event WorkflowPrefixBound(bytes32 indexed workflowId, bytes1 prefix);

    // ================================================================
    //                        USER FUNCTIONS
    // ================================================================

    /// @notice Deposit ETH into the vault with World ID proof verification
    /// @param worldIdRoot The World ID Merkle root
    /// @param nullifierHash The World ID nullifier hash (unique per user per action)
    /// @param proof The World ID zero-knowledge proof
    function deposit(
        uint256 worldIdRoot,
        uint256 nullifierHash,
        uint256[8] calldata proof
    ) external payable;

    /// @notice Withdraw assets from the vault with World ID proof verification
    /// @param shares The number of vault shares to redeem
    /// @param worldIdRoot The World ID Merkle root
    /// @param nullifierHash The World ID nullifier hash
    /// @param proof The World ID zero-knowledge proof
    function withdraw(
        uint256 shares,
        uint256 worldIdRoot,
        uint256 nullifierHash,
        uint256[8] calldata proof
    ) external;

    // ================================================================
    //                        VIEW FUNCTIONS
    // ================================================================

    /// @notice Get a user's position in the vault
    /// @param user The user address
    /// @return The user's Position struct
    function getPosition(address user) external view returns (Position memory);

    /// @notice Get the total assets managed by the vault
    /// @return Total assets in wei
    function getTotalAssets() external view returns (uint256);

    /// @notice Check if the circuit breaker is currently active
    /// @return True if the circuit breaker is active
    function isCircuitBreakerActive() external view returns (bool);

    /// @notice Convert shares to underlying asset amount
    /// @param shares Number of shares
    /// @return assets Equivalent asset amount
    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    /// @notice Convert asset amount to shares
    /// @param assets Amount of assets
    /// @return shares Equivalent share amount
    function convertToShares(uint256 assets) external view returns (uint256 shares);
}
