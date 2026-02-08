// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Events - Shared event definitions for the AEGIS Protocol
/// @notice Centralized event definitions used across multiple contracts
library Events {
    /// @notice Emitted when a CRE report is received and processed
    /// @param reportId Unique identifier for the report
    /// @param prefix The action prefix byte from the report
    /// @param timestamp When the report was processed
    event ReportReceived(bytes32 indexed reportId, bytes1 indexed prefix, uint256 timestamp);

    /// @notice Emitted when the protocol is paused
    /// @param account The address that triggered the pause
    event ProtocolPaused(address indexed account);

    /// @notice Emitted when the protocol is unpaused
    /// @param account The address that triggered the unpause
    event ProtocolUnpaused(address indexed account);

    /// @notice Emitted when an emergency action is taken
    /// @param action Description of the emergency action
    /// @param caller The address that triggered the action
    event EmergencyAction(string action, address indexed caller);
}
