// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {AegisVault} from "../src/core/AegisVault.sol";
import {RiskRegistry} from "../src/core/RiskRegistry.sol";
import {StrategyRouter} from "../src/core/StrategyRouter.sol";
import {WorldIdGate} from "../src/access/WorldIdGate.sol";

/// @title VerifyContracts - Post-deployment smoke test
/// @notice Reads all cross-references and validates configuration
/// @dev Run: forge script script/VerifyContracts.s.sol --rpc-url $SEPOLIA_RPC
contract VerifyContracts is Script {
    function run() external view {
        address vaultAddr = vm.envAddress("AEGIS_VAULT");
        address registryAddr = vm.envAddress("RISK_REGISTRY");
        address routerAddr = vm.envAddress("STRATEGY_ROUTER");
        address gateAddr = vm.envAddress("WORLD_ID_GATE");

        AegisVault vault = AegisVault(payable(vaultAddr));
        RiskRegistry registry = RiskRegistry(registryAddr);
        StrategyRouter router = StrategyRouter(payable(routerAddr));
        WorldIdGate gate = WorldIdGate(gateAddr);

        console2.log("=== AEGIS Protocol Verification ===");
        console2.log("");

        // Check AegisVault references
        console2.log("--- AegisVault ---");
        console2.log("Address:         ", vaultAddr);
        console2.log("RiskRegistry:    ", vault.riskRegistry());
        console2.log("StrategyRouter:  ", vault.strategyRouter());
        console2.log("WorldIdGate:     ", vault.worldIdGate());
        console2.log("Setup Complete:  ", vault.isSetupComplete());
        console2.log("CB Active:       ", vault.isCircuitBreakerActive());
        console2.log("Total Assets:    ", vault.getTotalAssets());
        console2.log("Min Deposit:     ", vault.minDeposit());
        console2.log("");

        // Validate cross-references
        bool vaultOk = true;
        if (vault.riskRegistry() != registryAddr) {
            console2.log("FAIL: Vault.riskRegistry mismatch!");
            vaultOk = false;
        }
        if (vault.strategyRouter() != routerAddr) {
            console2.log("FAIL: Vault.strategyRouter mismatch!");
            vaultOk = false;
        }
        if (vault.worldIdGate() != gateAddr) {
            console2.log("FAIL: Vault.worldIdGate mismatch!");
            vaultOk = false;
        }
        if (!vault.isSetupComplete()) {
            console2.log("FAIL: Vault setup not complete!");
            vaultOk = false;
        }

        // Check RiskRegistry
        console2.log("--- RiskRegistry ---");
        console2.log("Address:         ", registryAddr);
        console2.log("Threshold:       ", registry.riskThreshold());
        console2.log("Vault authorized:", registry.isAuthorizedVault(vaultAddr));
        console2.log("CB Active:       ", registry.isCircuitBreakerActive());
        console2.log("");

        if (!registry.isAuthorizedVault(vaultAddr)) {
            console2.log("FAIL: Vault not authorized in RiskRegistry!");
            vaultOk = false;
        }

        // Check StrategyRouter
        console2.log("--- StrategyRouter ---");
        console2.log("Address:         ", routerAddr);
        console2.log("Vault:           ", router.vault());
        console2.log("Transfer Budget: ", router.getRemainingTransferBudget());
        console2.log("");

        if (router.vault() != vaultAddr) {
            console2.log("FAIL: Router.vault mismatch!");
            vaultOk = false;
        }

        // Check WorldIdGate
        console2.log("--- WorldIdGate ---");
        console2.log("Address:         ", gateAddr);
        console2.log("Vault authorized:", gate.isAuthorizedVault(vaultAddr));
        console2.log("Verification TTL:", gate.verificationTTL());
        console2.log("");

        if (!gate.isAuthorizedVault(vaultAddr)) {
            console2.log("FAIL: Vault not authorized in WorldIdGate!");
            vaultOk = false;
        }

        // Final result
        console2.log("=================================");
        if (vaultOk) {
            console2.log("ALL CHECKS PASSED");
        } else {
            console2.log("SOME CHECKS FAILED - review above");
        }
    }
}
