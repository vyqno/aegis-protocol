// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IReceiver} from "../../src/interfaces/IReceiver.sol";

/// @title MockForwarder - Test mock replicating KeystoneForwarder metadata encoding
/// @notice Accurately replicates the metadata format used by Chainlink's KeystoneForwarder
///         to ensure tests match production behavior (VULN-005)
/// @dev Metadata is encoded as: abi.encodePacked(workflowId, workflowName, workflowOwner)
///      - workflowId: bytes32 (32 bytes)
///      - workflowName: bytes10 (10 bytes)
///      - workflowOwner: address (20 bytes)
///      Total: 62 bytes
contract MockForwarder {
    // ================================================================
    //                           EVENTS
    // ================================================================

    event ReportDelivered(
        address indexed receiver,
        bytes32 indexed workflowId,
        bool success
    );

    // ================================================================
    //                           ERRORS
    // ================================================================

    error DeliveryFailed(address receiver, bytes returnData);

    // ================================================================
    //                      DELIVERY FUNCTIONS
    // ================================================================

    /// @notice Deliver a report to a receiver contract with full metadata
    /// @param receiver The receiver contract address
    /// @param workflowId The workflow ID (bytes32)
    /// @param workflowName The workflow name (bytes10)
    /// @param workflowOwner The workflow owner address
    /// @param report The report data
    function deliverReport(
        address receiver,
        bytes32 workflowId,
        bytes10 workflowName,
        address workflowOwner,
        bytes calldata report
    ) external {
        bytes memory metadata = _encodeMetadata(workflowId, workflowName, workflowOwner);
        IReceiver(receiver).onReport(metadata, report);
        emit ReportDelivered(receiver, workflowId, true);
    }

    /// @notice Deliver a report with raw metadata (for testing edge cases)
    /// @param receiver The receiver contract address
    /// @param metadata Raw metadata bytes
    /// @param report The report data
    function deliverReportRaw(
        address receiver,
        bytes calldata metadata,
        bytes calldata report
    ) external {
        IReceiver(receiver).onReport(metadata, report);
    }

    // ================================================================
    //                      ENCODING FUNCTIONS
    // ================================================================

    /// @notice Encode metadata in the exact format used by KeystoneForwarder
    /// @param workflowId The workflow ID
    /// @param workflowName The workflow name
    /// @param workflowOwner The workflow owner address
    /// @return metadata The packed metadata bytes (62 bytes)
    /// @dev Format: abi.encodePacked(workflowId, workflowName, workflowOwner)
    ///      This matches the encoding used by _decodeMetadata in ReceiverTemplate
    function _encodeMetadata(
        bytes32 workflowId,
        bytes10 workflowName,
        address workflowOwner
    ) internal pure returns (bytes memory metadata) {
        metadata = abi.encodePacked(workflowId, workflowName, workflowOwner);
    }

    /// @notice Public helper to generate metadata for off-chain test setup
    /// @param workflowId The workflow ID
    /// @param workflowName The workflow name
    /// @param workflowOwner The workflow owner address
    /// @return The encoded metadata bytes
    function encodeMetadata(
        bytes32 workflowId,
        bytes10 workflowName,
        address workflowOwner
    ) external pure returns (bytes memory) {
        return _encodeMetadata(workflowId, workflowName, workflowOwner);
    }
}
