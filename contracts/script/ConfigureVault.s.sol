// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {AegisVault} from "../src/core/AegisVault.sol";
import {RiskRegistry} from "../src/core/RiskRegistry.sol";
import {StrategyRouter} from "../src/core/StrategyRouter.sol";

/// @title ConfigureVault - Post-deployment configuration for workflow bindings
/// @notice Sets workflow-to-prefix bindings and target allocations after CRE workflows are deployed
/// @dev Run after deploying contracts AND CRE workflows (need workflow IDs)
///      forge script script/ConfigureVault.s.sol --rpc-url $SEPOLIA_RPC --broadcast
contract ConfigureVault is Script {
    uint64 constant SEPOLIA_CHAIN_SELECTOR = 16015286601757825753;
    uint64 constant BASE_SEPOLIA_CHAIN_SELECTOR = 10344971235874465080;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // Deployed contract addresses (from Deploy.s.sol output)
        address vaultAddr = vm.envAddress("AEGIS_VAULT");
        address registryAddr = vm.envAddress("RISK_REGISTRY");
        address routerAddr = vm.envAddress("STRATEGY_ROUTER");

        // CRE Workflow IDs (from `cre workflow deploy` output)
        bytes32 yieldScannerWorkflowId = vm.envBytes32("YIELD_SCANNER_WORKFLOW_ID");
        bytes32 riskSentinelWorkflowId = vm.envBytes32("RISK_SENTINEL_WORKFLOW_ID");
        bytes32 vaultManagerWorkflowId = vm.envBytes32("VAULT_MANAGER_WORKFLOW_ID");

        AegisVault vault = AegisVault(payable(vaultAddr));
        StrategyRouter router = StrategyRouter(payable(routerAddr));

        console2.log("=== AEGIS Vault Configuration ===");
        console2.log("Vault:", vaultAddr);

        vm.startBroadcast(deployerPrivateKey);

        // ============================================================
        // Step 1: Bind workflow IDs to report prefixes
        // ============================================================
        // 0x01 = yield scanner report
        vault.setWorkflowPrefix(yieldScannerWorkflowId, bytes1(0x01));
        console2.log("Bound yield-scanner workflow -> prefix 0x01");

        // 0x02 = risk sentinel report
        vault.setWorkflowPrefix(riskSentinelWorkflowId, bytes1(0x02));
        console2.log("Bound risk-sentinel workflow -> prefix 0x02");

        // 0x03 = vault manager operation
        vault.setWorkflowPrefix(vaultManagerWorkflowId, bytes1(0x03));
        console2.log("Bound vault-manager workflow -> prefix 0x03");

        // ============================================================
        // Step 2: Set target allocations (60% Sepolia, 40% Base)
        // ============================================================
        uint64[] memory chains = new uint64[](2);
        chains[0] = SEPOLIA_CHAIN_SELECTOR;
        chains[1] = BASE_SEPOLIA_CHAIN_SELECTOR;

        uint256[] memory allocations = new uint256[](2);
        allocations[0] = 6000; // 60% on Sepolia
        allocations[1] = 4000; // 40% on Base Sepolia

        router.setTargetAllocations(chains, allocations);
        console2.log("Target allocations set: Sepolia 60%, Base 40%");

        // ============================================================
        // Step 3: Authorize risk sentinel workflow as sentinel
        // ============================================================
        // The risk sentinel CRE workflow writes reports through the forwarder,
        // which calls onReport on the vault. The vault then calls activateCircuitBreaker
        // on the registry. The vault is already registered, so this path works.
        // For direct sentinel calls (testing), authorize the deployer:
        address deployer = vm.addr(deployerPrivateKey);
        RiskRegistry(registryAddr).setSentinelAuthorization(deployer, true);
        console2.log("Deployer authorized as sentinel for testing");

        vm.stopBroadcast();

        // ============================================================
        // Verification
        // ============================================================
        console2.log("");
        console2.log("=== Configuration Complete ===");
        console2.log("Verify with:");
        console2.log("  cast call", vaultAddr, "\"getWorkflowPrefix(bytes32)\"", vm.toString(yieldScannerWorkflowId));
        console2.log("  cast call", vaultAddr, "\"isSetupComplete()\"");
    }
}
