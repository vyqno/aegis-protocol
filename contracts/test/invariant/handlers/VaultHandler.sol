// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AegisVault} from "../../../src/core/AegisVault.sol";
import {IAegisVault} from "../../../src/interfaces/IAegisVault.sol";

/// @title VaultHandler - Bounded action handler for AegisVault invariant testing
/// @dev Exposes bounded deposit/withdraw actions for the invariant test runner
contract VaultHandler is Test {
    AegisVault public vault;

    // Track ghost variables for invariant assertions
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalWithdrawn;
    uint256 public ghost_depositCount;
    uint256 public ghost_withdrawCount;

    address[] public actors;
    uint256[8] emptyProof;

    constructor(AegisVault _vault) {
        vault = _vault;

        // Create bounded set of actors
        for (uint256 i = 0; i < 5; i++) {
            address actor = address(uint160(0x1000 + i));
            actors.push(actor);
            vm.deal(actor, 100 ether);
        }
    }

    /// @notice Bounded deposit action
    function deposit(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        amount = bound(amount, 0.001 ether, 10 ether);

        vm.prank(actor);
        vault.deposit{value: amount}(0, 0, emptyProof);

        ghost_totalDeposited += amount;
        ghost_depositCount++;
    }

    /// @notice Bounded withdraw action
    function withdraw(uint256 actorSeed, uint256 sharePct) external {
        address actor = actors[actorSeed % actors.length];
        IAegisVault.Position memory pos = vault.getPosition(actor);

        if (pos.shares == 0) return; // Skip if no position

        sharePct = bound(sharePct, 1, 100);
        uint256 shares = (pos.shares * sharePct) / 100;
        if (shares == 0) shares = 1;

        // Advance past hold period
        vm.warp(block.timestamp + 2 hours);

        uint256 balBefore = actor.balance;
        vm.prank(actor);
        vault.withdraw(shares, 0, 0, emptyProof);

        ghost_totalWithdrawn += (actor.balance - balBefore);
        ghost_withdrawCount++;
    }
}
