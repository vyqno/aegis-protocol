// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AegisVault} from "../../src/core/AegisVault.sol";
import {IAegisVault} from "../../src/interfaces/IAegisVault.sol";
import {MockForwarder} from "../helpers/MockForwarder.sol";
import {VaultHandler} from "./handlers/VaultHandler.sol";

/// @title AegisVaultInvariantTest - Invariant tests for vault share math and state
/// @dev Uses VaultHandler for bounded actions. Verifies virtual share protection,
///      total assets consistency, and conversion roundtrip safety.
contract AegisVaultInvariantTest is Test {
    AegisVault public vault;
    MockForwarder public forwarder;
    VaultHandler public handler;

    function setUp() public {
        forwarder = new MockForwarder();
        vault = new AegisVault(address(forwarder));

        vault.setWorkflowPrefix(bytes32(uint256(1)), bytes1(0x01));
        vault.setWorkflowPrefix(bytes32(uint256(2)), bytes1(0x02));
        vault.completeInitialSetup();

        handler = new VaultHandler(vault);

        // Target only the handler for invariant calls
        targetContract(address(handler));
    }

    // ================================================================
    //                  VIRTUAL SHARES INVARIANT
    // ================================================================

    /// @notice INVARIANT: totalShares + VIRTUAL_SHARES > 0 (prevents division by zero)
    function invariant_virtualSharesPositive() public view {
        assertGt(
            vault.totalShares() + vault.VIRTUAL_SHARES(),
            0,
            "totalShares + VIRTUAL_SHARES must always be > 0"
        );
    }

    /// @notice INVARIANT: totalAssets + VIRTUAL_ASSETS > 0 (prevents inflation attack)
    function invariant_virtualAssetsPositive() public view {
        assertGt(
            vault.getTotalAssets() + vault.VIRTUAL_ASSETS(),
            0,
            "totalAssets + VIRTUAL_ASSETS must always be > 0"
        );
    }

    // ================================================================
    //              CONVERSION ROUNDTRIP INVARIANT
    // ================================================================

    /// @notice INVARIANT: convertToAssets(convertToShares(x)) <= x (no rounding profit)
    function invariant_noRoundingProfit() public view {
        uint256 testAmount = 1 ether;
        uint256 shares = vault.convertToShares(testAmount);
        uint256 assetsBack = vault.convertToAssets(shares);

        assertLe(assetsBack, testAmount, "Conversion roundtrip must not produce profit");
    }

    // ================================================================
    //              TOTAL ASSETS CONSISTENCY INVARIANT
    // ================================================================

    /// @notice INVARIANT: Total withdrawn <= total deposited (vault never creates money)
    function invariant_withdrawalsNeverExceedDeposits() public view {
        assertLe(
            handler.ghost_totalWithdrawn(),
            handler.ghost_totalDeposited(),
            "Total withdrawn must never exceed total deposited"
        );
    }

    // ================================================================
    //                 SETUP FLAG INVARIANT
    // ================================================================

    /// @notice INVARIANT: Setup flag is always true after initial setup
    function invariant_setupAlwaysComplete() public view {
        assertTrue(vault.isSetupComplete(), "Setup must remain complete");
    }
}
