// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Errors - Shared custom errors for the AEGIS Protocol
/// @notice Centralized error definitions used across multiple contracts
library Errors {
    /// @notice Thrown when address(0) is provided where a valid address is required
    error ZeroAddress();

    /// @notice Thrown when a zero amount is provided where a non-zero value is required
    error ZeroAmount();

    /// @notice Thrown when an operation is attempted while the circuit breaker is active
    error CircuitBreakerActive();

    /// @notice Thrown when the caller is not authorized for an operation
    error Unauthorized(address caller);

    /// @notice Thrown when the contract setup has not been completed
    error SetupNotComplete();

    /// @notice Thrown when an ETH transfer fails
    error TransferFailed();

    /// @notice Thrown when the contract is in an unexpected state for the operation
    error InvalidState();

    /// @notice Thrown when an array length mismatch occurs
    error ArrayLengthMismatch(uint256 expected, uint256 actual);

    /// @notice Thrown when a value exceeds the maximum allowed
    error ExceedsMaximum(uint256 value, uint256 maximum);

    /// @notice Thrown when a value is below the minimum allowed
    error BelowMinimum(uint256 value, uint256 minimum);

    /// @notice Thrown when a report with this ID has already been processed
    error ReportAlreadyProcessed(bytes32 reportId);
}
