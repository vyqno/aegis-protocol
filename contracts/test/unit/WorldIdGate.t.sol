// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {WorldIdGate, IWorldID} from "../../src/access/WorldIdGate.sol";
import {IWorldIdGate} from "../../src/interfaces/IWorldIdGate.sol";
import {MockWorldId} from "../helpers/MockWorldId.sol";
import {TestConstants} from "../helpers/TestConstants.sol";

/// @title WorldIdGateTest - Comprehensive unit tests for WorldIdGate
/// @dev Covers verification, anti-front-running, TTL expiry, revocation, re-verification,
///      vault-mediated calls, and admin functions
contract WorldIdGateTest is Test {
    WorldIdGate public gate;
    MockWorldId public mockWorldId;

    address public owner;
    address public user1;
    address public user2;
    address public vaultAddr;

    uint256 constant TEST_GROUP_ID = 1;
    string constant TEST_ACTION_ID = "AEGIS-VERIFY-V1";
    uint256 constant TEST_TTL = 24 hours;

    // Test proof parameters
    uint256 constant TEST_ROOT = 12345;
    uint256 constant TEST_NULLIFIER_1 = 111111;
    uint256 constant TEST_NULLIFIER_2 = 222222;
    uint256 constant TEST_NULLIFIER_3 = 333333;
    uint256[8] testProof;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        vaultAddr = makeAddr("vault");

        // Deploy mock World ID verifier
        mockWorldId = new MockWorldId();

        // Deploy WorldIdGate
        gate = new WorldIdGate(
            address(mockWorldId),
            TEST_GROUP_ID,
            TEST_ACTION_ID,
            TEST_TTL
        );

        // Register vault as authorized caller
        gate.registerVault(vaultAddr);
    }

    // ================================================================
    //                   CONSTRUCTOR TESTS
    // ================================================================

    function test_constructor_sets_initial_state() public view {
        assertEq(address(gate.worldId()), address(mockWorldId));
        assertEq(gate.groupId(), TEST_GROUP_ID);
        assertEq(gate.verificationTTL(), TEST_TTL);
        assertTrue(gate.isAuthorizedVault(vaultAddr));
    }

    function test_constructor_reverts_zero_worldId() public {
        vm.expectRevert(IWorldIdGate.ZeroAddress.selector);
        new WorldIdGate(address(0), TEST_GROUP_ID, TEST_ACTION_ID, TEST_TTL);
    }

    function test_constructor_reverts_ttl_too_low() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IWorldIdGate.VerificationTTLOutOfBounds.selector,
                30 minutes,
                gate.MIN_TTL(),
                gate.MAX_TTL()
            )
        );
        new WorldIdGate(address(mockWorldId), TEST_GROUP_ID, TEST_ACTION_ID, 30 minutes);
    }

    function test_constructor_reverts_ttl_too_high() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IWorldIdGate.VerificationTTLOutOfBounds.selector,
                31 days,
                gate.MIN_TTL(),
                gate.MAX_TTL()
            )
        );
        new WorldIdGate(address(mockWorldId), TEST_GROUP_ID, TEST_ACTION_ID, 31 days);
    }

    // ================================================================
    //              VERIFY IDENTITY TESTS (DIRECT CALL)
    // ================================================================

    function test_verifyIdentity_with_valid_proof() public {
        vm.prank(user1);
        gate.verifyIdentity(user1, TEST_ROOT, TEST_NULLIFIER_1, testProof);

        assertTrue(gate.isVerified(user1), "User should be verified");

        IWorldIdGate.VerificationRecord memory record = gate.getVerificationRecord(user1);
        assertTrue(record.isVerified);
        assertEq(record.nullifierHash, TEST_NULLIFIER_1);
        assertEq(record.verifiedAt, block.timestamp);
        assertEq(record.expiresAt, block.timestamp + TEST_TTL);
    }

    function test_verifyIdentity_emits_event() public {
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit IWorldIdGate.IdentityVerified(user1, TEST_NULLIFIER_1, block.timestamp + TEST_TTL);
        gate.verifyIdentity(user1, TEST_ROOT, TEST_NULLIFIER_1, testProof);
    }

    function test_verifyIdentity_reverts_signal_not_msg_sender() public {
        // CRITICAL: user2 tries to verify user1's identity (front-running attack)
        vm.prank(user2);
        vm.expectRevert(
            abi.encodeWithSelector(IWorldIdGate.SignalMismatch.selector, user1, user2)
        );
        gate.verifyIdentity(user1, TEST_ROOT, TEST_NULLIFIER_1, testProof);
    }

    function test_verifyIdentity_reverts_with_invalid_proof() public {
        mockWorldId.setShouldRevert(true);

        vm.prank(user1);
        vm.expectRevert("MockWorldId: invalid proof");
        gate.verifyIdentity(user1, TEST_ROOT, TEST_NULLIFIER_1, testProof);
    }

    function test_verifyIdentity_reverts_with_duplicate_nullifier() public {
        // First verification succeeds
        vm.prank(user1);
        gate.verifyIdentity(user1, TEST_ROOT, TEST_NULLIFIER_1, testProof);

        // Revoke so user1 needs re-verification
        gate.revokeVerification(user1);

        // Same nullifier should fail
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(IWorldIdGate.NullifierAlreadyUsed.selector, TEST_NULLIFIER_1)
        );
        gate.verifyIdentity(user1, TEST_ROOT, TEST_NULLIFIER_1, testProof);
    }

    function test_verifyIdentity_is_idempotent_when_already_verified() public {
        // First verification
        vm.prank(user1);
        gate.verifyIdentity(user1, TEST_ROOT, TEST_NULLIFIER_1, testProof);
        assertTrue(gate.isVerified(user1));

        // Second call with same user should be a no-op (idempotent)
        // The nullifier_2 should NOT be consumed because we return early
        vm.prank(user1);
        gate.verifyIdentity(user1, TEST_ROOT, TEST_NULLIFIER_2, testProof);

        // Nullifier 2 should still be available (not consumed by idempotent call)
        assertFalse(gate.nullifierHashes(TEST_NULLIFIER_2), "Nullifier 2 should not be consumed");
    }

    function test_verifyIdentity_re_verifies_after_ttl_expires() public {
        // First verification
        vm.prank(user1);
        gate.verifyIdentity(user1, TEST_ROOT, TEST_NULLIFIER_1, testProof);
        assertTrue(gate.isVerified(user1));

        // Advance past TTL
        vm.warp(block.timestamp + TEST_TTL + 1);
        assertFalse(gate.isVerified(user1), "Should be expired");

        // New verification with new nullifier should work
        vm.prank(user1);
        gate.verifyIdentity(user1, TEST_ROOT, TEST_NULLIFIER_2, testProof);

        assertTrue(gate.isVerified(user1), "Should be re-verified");
        assertTrue(gate.nullifierHashes(TEST_NULLIFIER_2), "New nullifier should be consumed");
    }

    // ================================================================
    //              VERIFY IDENTITY TESTS (VAULT-MEDIATED)
    // ================================================================

    function test_verifyIdentity_succeeds_from_authorized_vault() public {
        // Vault calls verifyIdentity on behalf of user1
        vm.prank(vaultAddr);
        gate.verifyIdentity(user1, TEST_ROOT, TEST_NULLIFIER_1, testProof);

        assertTrue(gate.isVerified(user1), "User should be verified via vault");
    }

    function test_verifyIdentity_reverts_from_unauthorized_vault() public {
        address fakeVault = makeAddr("fakeVault");

        vm.prank(fakeVault);
        vm.expectRevert(
            abi.encodeWithSelector(IWorldIdGate.SignalMismatch.selector, user1, fakeVault)
        );
        gate.verifyIdentity(user1, TEST_ROOT, TEST_NULLIFIER_1, testProof);
    }

    function test_verifyIdentity_idempotent_from_vault() public {
        // Initial verification
        vm.prank(vaultAddr);
        gate.verifyIdentity(user1, TEST_ROOT, TEST_NULLIFIER_1, testProof);
        assertTrue(gate.isVerified(user1));

        // Subsequent call from vault should be a no-op
        vm.prank(vaultAddr);
        gate.verifyIdentity(user1, TEST_ROOT, 0, testProof);

        // Original nullifier should still be recorded, but 0 should NOT be consumed
        assertTrue(gate.nullifierHashes(TEST_NULLIFIER_1), "Original nullifier consumed");
        assertFalse(gate.nullifierHashes(0), "Zero nullifier should not be consumed");
    }

    // ================================================================
    //                    IS VERIFIED TESTS
    // ================================================================

    function test_isVerified_returns_true_after_registration() public {
        vm.prank(user1);
        gate.verifyIdentity(user1, TEST_ROOT, TEST_NULLIFIER_1, testProof);

        assertTrue(gate.isVerified(user1));
    }

    function test_isVerified_returns_false_before_registration() public view {
        assertFalse(gate.isVerified(user1));
    }

    function test_isVerified_returns_false_after_ttl_expires() public {
        vm.prank(user1);
        gate.verifyIdentity(user1, TEST_ROOT, TEST_NULLIFIER_1, testProof);
        assertTrue(gate.isVerified(user1));

        // Advance past TTL
        vm.warp(block.timestamp + TEST_TTL + 1);
        assertFalse(gate.isVerified(user1), "Should be expired after TTL");
    }

    function test_isVerified_returns_true_at_exact_expiry() public {
        vm.prank(user1);
        gate.verifyIdentity(user1, TEST_ROOT, TEST_NULLIFIER_1, testProof);

        // At exact expiry timestamp, still valid (> not >=)
        vm.warp(block.timestamp + TEST_TTL);
        assertTrue(gate.isVerified(user1), "Should still be valid at exact expiry");
    }

    // ================================================================
    //                   REVOCATION TESTS
    // ================================================================

    function test_revokeVerification_by_owner() public {
        vm.prank(user1);
        gate.verifyIdentity(user1, TEST_ROOT, TEST_NULLIFIER_1, testProof);
        assertTrue(gate.isVerified(user1));

        gate.revokeVerification(user1);
        assertFalse(gate.isVerified(user1), "Should be revoked");

        IWorldIdGate.VerificationRecord memory record = gate.getVerificationRecord(user1);
        assertFalse(record.isVerified, "Record should show not verified");
    }

    function test_revokeVerification_emits_event() public {
        vm.prank(user1);
        gate.verifyIdentity(user1, TEST_ROOT, TEST_NULLIFIER_1, testProof);

        vm.expectEmit(true, true, false, false);
        emit IWorldIdGate.VerificationRevoked(user1, TEST_NULLIFIER_1);
        gate.revokeVerification(user1);
    }

    function test_revokeVerification_allows_re_verification_with_new_proof() public {
        // Initial verification
        vm.prank(user1);
        gate.verifyIdentity(user1, TEST_ROOT, TEST_NULLIFIER_1, testProof);
        assertTrue(gate.isVerified(user1));

        // Revoke
        gate.revokeVerification(user1);
        assertFalse(gate.isVerified(user1));

        // Re-verify with NEW nullifier (old one is burned)
        vm.prank(user1);
        gate.verifyIdentity(user1, TEST_ROOT, TEST_NULLIFIER_2, testProof);
        assertTrue(gate.isVerified(user1), "Should be re-verified with new proof");
    }

    function test_revokeVerification_reverts_from_non_owner() public {
        vm.prank(user1);
        gate.verifyIdentity(user1, TEST_ROOT, TEST_NULLIFIER_1, testProof);

        vm.prank(user1);
        vm.expectRevert();
        gate.revokeVerification(user1);
    }

    // ================================================================
    //                   TTL CONFIGURATION TESTS
    // ================================================================

    function test_setVerificationTTL_by_owner() public {
        uint256 newTTL = 48 hours;

        vm.expectEmit(false, false, false, true);
        emit IWorldIdGate.VerificationTTLUpdated(TEST_TTL, newTTL);
        gate.setVerificationTTL(newTTL);

        assertEq(gate.verificationTTL(), newTTL);
    }

    function test_setVerificationTTL_reverts_below_min() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IWorldIdGate.VerificationTTLOutOfBounds.selector,
                30 minutes,
                gate.MIN_TTL(),
                gate.MAX_TTL()
            )
        );
        gate.setVerificationTTL(30 minutes);
    }

    function test_setVerificationTTL_reverts_above_max() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IWorldIdGate.VerificationTTLOutOfBounds.selector,
                31 days,
                gate.MIN_TTL(),
                gate.MAX_TTL()
            )
        );
        gate.setVerificationTTL(31 days);
    }

    function test_setVerificationTTL_reverts_from_non_owner() public {
        vm.prank(user1);
        vm.expectRevert();
        gate.setVerificationTTL(48 hours);
    }

    // ================================================================
    //                 VAULT REGISTRATION TESTS
    // ================================================================

    function test_registerVault() public {
        address newVault = makeAddr("newVault");

        vm.expectEmit(true, false, false, false);
        emit IWorldIdGate.VaultRegistered(newVault);
        gate.registerVault(newVault);

        assertTrue(gate.isAuthorizedVault(newVault));
    }

    function test_registerVault_reverts_zero_address() public {
        vm.expectRevert(IWorldIdGate.ZeroAddress.selector);
        gate.registerVault(address(0));
    }

    function test_removeVault() public {
        gate.removeVault(vaultAddr);
        assertFalse(gate.isAuthorizedVault(vaultAddr));
    }

    // ================================================================
    //              WORLD ID CONFIG UPDATE TESTS
    // ================================================================

    function test_setWorldIdContract() public {
        MockWorldId newMock = new MockWorldId();
        address oldAddr = address(mockWorldId);

        vm.expectEmit(true, true, false, false);
        emit IWorldIdGate.WorldIdContractUpdated(oldAddr, address(newMock));
        gate.setWorldIdContract(address(newMock));

        assertEq(address(gate.worldId()), address(newMock));
    }

    function test_setWorldIdContract_reverts_zero_address() public {
        vm.expectRevert(IWorldIdGate.ZeroAddress.selector);
        gate.setWorldIdContract(address(0));
    }

    function test_setGroupId() public {
        vm.expectEmit(false, false, false, true);
        emit IWorldIdGate.GroupIdUpdated(TEST_GROUP_ID, 2);
        gate.setGroupId(2);

        assertEq(gate.groupId(), 2);
    }

    function test_setActionId() public {
        gate.setActionId("NEW-ACTION-V2");
        // ExternalNullifierHash should have changed
        // We can verify by doing a new verification (it will use the new hash)
    }

    // ================================================================
    //                      PAUSE TESTS
    // ================================================================

    function test_pause_blocks_verification() public {
        gate.pause();

        vm.prank(user1);
        vm.expectRevert();
        gate.verifyIdentity(user1, TEST_ROOT, TEST_NULLIFIER_1, testProof);
    }

    function test_unpause_allows_verification() public {
        gate.pause();
        gate.unpause();

        vm.prank(user1);
        gate.verifyIdentity(user1, TEST_ROOT, TEST_NULLIFIER_1, testProof);
        assertTrue(gate.isVerified(user1));
    }

    function test_isVerified_still_works_when_paused() public {
        // Verify first
        vm.prank(user1);
        gate.verifyIdentity(user1, TEST_ROOT, TEST_NULLIFIER_1, testProof);

        // Pause
        gate.pause();

        // isVerified is a view function - should still work
        assertTrue(gate.isVerified(user1));
    }

    // ================================================================
    //                OWNABLE2STEP PATTERN TESTS
    // ================================================================

    function test_transferOwnership_is_two_step() public {
        address newOwner = makeAddr("newOwner");

        gate.transferOwnership(newOwner);
        assertEq(gate.owner(), address(this), "Owner should not change yet");
        assertEq(gate.pendingOwner(), newOwner);

        vm.prank(newOwner);
        gate.acceptOwnership();
        assertEq(gate.owner(), newOwner);
    }
}
