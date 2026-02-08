// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title TestConstants - Shared constants for AEGIS Protocol tests
/// @notice Centralized test configuration to avoid magic numbers in test files
library TestConstants {
    // ================================================================
    //                    FORWARDER ADDRESSES
    // ================================================================

    /// @notice Chainlink KeystoneForwarder on Ethereum Sepolia
    address internal constant SEPOLIA_FORWARDER = 0x15fC6ae953E024d975e77382eEeC56A9101f9F88;

    /// @notice Chainlink KeystoneForwarder on Base Sepolia
    address internal constant BASE_SEPOLIA_FORWARDER = 0x82300bd7c3958625581cc2F77bC6464dcEcDF3e5;

    // ================================================================
    //                    CCIP CHAIN SELECTORS
    // ================================================================

    /// @notice CCIP chain selector for Ethereum Sepolia
    uint64 internal constant SEPOLIA_CHAIN_SELECTOR = 16015286601757825753;

    /// @notice CCIP chain selector for Base Sepolia
    uint64 internal constant BASE_SEPOLIA_CHAIN_SELECTOR = 10344971235874465080;

    // ================================================================
    //                    TEST ADDRESSES
    // ================================================================

    /// @notice Default test owner address
    address internal constant TEST_OWNER = address(0x1);

    /// @notice Default test user address
    address internal constant TEST_USER = address(0x2);

    /// @notice Default test protocol address (e.g., Aave)
    address internal constant TEST_PROTOCOL = address(0x3);

    // ================================================================
    //                    WORKFLOW METADATA
    // ================================================================

    /// @notice Test workflow ID
    bytes32 internal constant TEST_WORKFLOW_ID = bytes32(uint256(1));

    /// @notice Test workflow name (bytes10)
    bytes10 internal constant TEST_WORKFLOW_NAME = bytes10("yield_scan");

    /// @notice Test workflow owner
    address internal constant TEST_WORKFLOW_OWNER = address(0xCAFE);

    // ================================================================
    //                    VAULT DEFAULTS
    // ================================================================

    /// @notice Default minimum deposit (0.01 ETH)
    uint256 internal constant DEFAULT_MIN_DEPOSIT = 0.01 ether;

    /// @notice Default minimum hold period (1 hour)
    uint256 internal constant DEFAULT_MIN_HOLD_PERIOD = 1 hours;

    /// @notice Default circuit breaker auto-deactivation period (72 hours)
    uint256 internal constant DEFAULT_AUTO_DEACTIVATION_PERIOD = 72 hours;

    // ================================================================
    //                    RISK DEFAULTS
    // ================================================================

    /// @notice Default risk threshold (70.00% = 7000 bps)
    uint256 internal constant DEFAULT_RISK_THRESHOLD = 7000;

    /// @notice Max circuit breaker activations per window
    uint256 internal constant DEFAULT_MAX_ACTIVATIONS_PER_WINDOW = 3;

    /// @notice Circuit breaker rate limit window (1 hour)
    uint256 internal constant DEFAULT_RATE_LIMIT_WINDOW = 1 hours;

    // ================================================================
    //                    WORLD ID DEFAULTS
    // ================================================================

    /// @notice Default verification TTL (24 hours)
    uint256 internal constant DEFAULT_VERIFICATION_TTL = 24 hours;
}
