// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MockWorldId - Test mock for World ID verifier
/// @notice Simulates IWorldID.verifyProof for testing WorldIdGate
/// @dev verifyProof MUST be view-compatible because IWorldID declares it as view.
///      State tracking is done via a separate non-view recordCall() function.
///      By default accepts all proofs. Set shouldRevert=true for negative testing.
contract MockWorldId {
    // ================================================================
    //                       STATE VARIABLES
    // ================================================================

    /// @notice When true, all verifyProof calls revert
    bool public shouldRevert;

    /// @notice Count of verifyProof calls (incremented externally via recordCall)
    uint256 public verifyCallCount;

    // ================================================================
    //                      CONFIGURATION
    // ================================================================

    /// @notice Set whether verifyProof should revert
    /// @param _shouldRevert True to make all calls revert
    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    /// @notice Manually increment the call counter (for test assertions)
    function incrementCallCount() external {
        verifyCallCount++;
    }

    /// @notice Reset state
    function reset() external {
        shouldRevert = false;
        verifyCallCount = 0;
    }

    // ================================================================
    //                      MOCK VERIFICATION
    // ================================================================

    /// @notice Mock implementation of IWorldID.verifyProof (view-compatible)
    /// @dev Must be view because WorldIdGate calls it via staticcall.
    ///      Only checks shouldRevert flag - cannot track state in view context.
    function verifyProof(
        uint256, /* root */
        uint256, /* groupId */
        uint256, /* signalHash */
        uint256, /* nullifierHash */
        uint256, /* externalNullifierHash */
        uint256[8] calldata /* proof */
    ) external view {
        if (shouldRevert) {
            revert("MockWorldId: invalid proof");
        }
        // Valid proof - no-op
    }
}
