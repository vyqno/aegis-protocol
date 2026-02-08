// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AegisVault} from "../../src/core/AegisVault.sol";
import {IAegisVault} from "../../src/interfaces/IAegisVault.sol";
import {MockForwarder} from "../helpers/MockForwarder.sol";

/// @title AegisVaultFuzzTest - Fuzz tests for deposit/withdraw and share math
/// @dev Focuses on virtual share inflation protection, rounding safety, and report handling
contract AegisVaultFuzzTest is Test {
    AegisVault public vault;
    MockForwarder public forwarder;

    address public user1;
    address public user2;

    bytes32 constant YIELD_WORKFLOW_ID = bytes32(uint256(1));
    bytes32 constant RISK_WORKFLOW_ID = bytes32(uint256(2));
    bytes10 constant TEST_WORKFLOW_NAME = bytes10("yield_scan");
    address constant TEST_WORKFLOW_OWNER = address(0xCAFE);

    uint256[8] emptyProof;

    function setUp() public {
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        forwarder = new MockForwarder();
        vault = new AegisVault(address(forwarder));

        vault.setWorkflowPrefix(YIELD_WORKFLOW_ID, bytes1(0x01));
        vault.setWorkflowPrefix(RISK_WORKFLOW_ID, bytes1(0x02));
        vault.completeInitialSetup();

        vm.deal(user1, 1000 ether);
        vm.deal(user2, 1000 ether);
    }

    // ================================================================
    //                     DEPOSIT FUZZ TESTS
    // ================================================================

    function testFuzz_deposit(uint256 amount) public {
        amount = bound(amount, 0.001 ether, 100 ether);

        vm.prank(user1);
        vault.deposit{value: amount}(0, 0, emptyProof);

        IAegisVault.Position memory pos = vault.getPosition(user1);
        assertGt(pos.shares, 0, "Should receive non-zero shares");
        assertEq(pos.depositAmount, amount, "Deposit amount should match");

        // INVARIANT: convertToAssets(shares) <= deposited amount (no rounding profit)
        uint256 assetsBack = vault.convertToAssets(pos.shares);
        assertLe(assetsBack, amount, "Cannot get more assets than deposited");
    }

    function testFuzz_deposit_multiple_users(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 0.001 ether, 50 ether);
        amount2 = bound(amount2, 0.001 ether, 50 ether);

        vm.prank(user1);
        vault.deposit{value: amount1}(0, 0, emptyProof);

        vm.prank(user2);
        vault.deposit{value: amount2}(0, 0, emptyProof);

        IAegisVault.Position memory pos1 = vault.getPosition(user1);
        IAegisVault.Position memory pos2 = vault.getPosition(user2);

        assertGt(pos1.shares, 0, "User1 should have shares");
        assertGt(pos2.shares, 0, "User2 should have shares");

        // Total assets should equal sum of deposits
        assertEq(vault.getTotalAssets(), amount1 + amount2, "Total assets mismatch");
    }

    // ================================================================
    //                    WITHDRAW FUZZ TESTS
    // ================================================================

    function testFuzz_withdraw(uint256 depositAmt, uint256 withdrawPct) public {
        depositAmt = bound(depositAmt, 0.001 ether, 100 ether);
        withdrawPct = bound(withdrawPct, 1, 100); // 1% to 100%

        vm.prank(user1);
        vault.deposit{value: depositAmt}(0, 0, emptyProof);

        IAegisVault.Position memory pos = vault.getPosition(user1);
        uint256 sharesToWithdraw = (pos.shares * withdrawPct) / 100;
        if (sharesToWithdraw == 0) sharesToWithdraw = 1;

        // Advance past hold period
        vm.warp(block.timestamp + 2 hours);

        uint256 balBefore = user1.balance;
        vm.prank(user1);
        vault.withdraw(sharesToWithdraw, 0, 0, emptyProof);

        uint256 received = user1.balance - balBefore;
        assertGt(received, 0, "Should receive ETH on withdrawal");
        assertLe(received, depositAmt, "Cannot withdraw more than deposited");
    }

    function testFuzz_withdraw_full(uint256 amount) public {
        amount = bound(amount, 0.001 ether, 100 ether);

        vm.prank(user1);
        vault.deposit{value: amount}(0, 0, emptyProof);

        IAegisVault.Position memory pos = vault.getPosition(user1);
        vm.warp(block.timestamp + 2 hours);

        uint256 balBefore = user1.balance;
        vm.prank(user1);
        vault.withdraw(pos.shares, 0, 0, emptyProof);

        uint256 received = user1.balance - balBefore;
        // With virtual shares, rounding loss is bounded
        assertGe(received, (amount * 99) / 100, "Full withdraw should return ~99%+ of deposit");
    }

    // ================================================================
    //              FIRST DEPOSITOR ATTACK FUZZ TEST
    // ================================================================

    /// @notice CRITICAL: Verifies virtual shares prevent inflation attack
    function testFuzz_firstDepositorAttack(uint256 donation, uint256 victimDeposit) public {
        donation = bound(donation, 1 wei, 100 ether);
        victimDeposit = bound(victimDeposit, 0.001 ether, 100 ether);

        // Attacker deposits minimum
        vm.prank(user1);
        vault.deposit{value: 0.001 ether}(0, 0, emptyProof);

        // Attacker donates ETH directly to vault (inflation attempt)
        vm.deal(address(this), donation);
        (bool ok,) = address(vault).call{value: donation}("");
        assertTrue(ok);

        // Victim deposits
        vm.prank(user2);
        vault.deposit{value: victimDeposit}(0, 0, emptyProof);

        IAegisVault.Position memory victimPos = vault.getPosition(user2);

        // INVARIANT: Victim MUST receive non-zero shares
        assertGt(victimPos.shares, 0, "Victim must get shares (virtual shares protection)");

        // Victim should get fair value (internal accounting ignores direct sends)
        uint256 victimAssets = vault.convertToAssets(victimPos.shares);
        assertGt(victimAssets, 0, "Victim assets must be non-zero");
    }

    // ================================================================
    //                  SHARE CONVERSION FUZZ TESTS
    // ================================================================

    function testFuzz_convertToShares_monotonic(uint256 a, uint256 b) public view {
        a = bound(a, 0.001 ether, 50 ether);
        b = bound(b, a, 100 ether);

        uint256 sharesA = vault.convertToShares(a);
        uint256 sharesB = vault.convertToShares(b);

        assertLe(sharesA, sharesB, "More assets should yield >= shares");
    }

    function testFuzz_convertToAssets_roundtrip(uint256 amount) public {
        amount = bound(amount, 0.001 ether, 50 ether);

        vm.prank(user1);
        vault.deposit{value: amount}(0, 0, emptyProof);

        IAegisVault.Position memory pos = vault.getPosition(user1);

        // INVARIANT: convertToAssets(convertToShares(x)) <= x (no rounding profit)
        uint256 shares = vault.convertToShares(amount);
        uint256 assetsBack = vault.convertToAssets(shares);
        assertLe(assetsBack, amount, "Roundtrip must not produce profit");
    }

    // ================================================================
    //                    REPORT DATA FUZZ TEST
    // ================================================================

    function testFuzz_processReport_malformed_graceful(bytes calldata extraData) public {
        // Only test with enough data for a prefix byte + some data
        vm.assume(extraData.length > 0 && extraData.length < 1000);

        bytes memory report = abi.encodePacked(bytes1(0x01), extraData);

        // Should either succeed or revert cleanly - never corrupt state
        try forwarder.deliverReport(
            address(vault),
            YIELD_WORKFLOW_ID,
            TEST_WORKFLOW_NAME,
            TEST_WORKFLOW_OWNER,
            report
        ) {
            // Success is fine
        } catch {
            // Clean revert is fine
        }

        // Vault state should never be corrupted
        assertEq(vault.getTotalAssets(), 0, "No deposits, total should be 0");
    }
}
