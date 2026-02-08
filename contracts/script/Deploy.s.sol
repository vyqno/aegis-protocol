// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {AegisVault} from "../src/core/AegisVault.sol";
import {RiskRegistry} from "../src/core/RiskRegistry.sol";
import {StrategyRouter} from "../src/core/StrategyRouter.sol";
import {WorldIdGate} from "../src/access/WorldIdGate.sol";

/// @title Deploy - Main deployment script for AEGIS Protocol on Ethereum Sepolia
/// @notice Deploys all contracts in paused/locked state, then configures cross-references
/// @dev Run: forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC --broadcast --verify
contract Deploy is Script {
    // ================================================================
    //                    DEPLOYMENT PARAMETERS
    // ================================================================

    /// @notice Chainlink KeystoneForwarder on Ethereum Sepolia
    address constant SEPOLIA_FORWARDER = 0x15fC6ae953E024d975e77382eEeC56A9101f9F88;

    /// @notice CCIP Router on Ethereum Sepolia
    address constant SEPOLIA_CCIP_ROUTER = 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59;

    /// @notice CCIP chain selector for Ethereum Sepolia
    uint64 constant SEPOLIA_CHAIN_SELECTOR = 16015286601757825753;

    /// @notice CCIP chain selector for Base Sepolia
    uint64 constant BASE_SEPOLIA_CHAIN_SELECTOR = 10344971235874465080;

    /// @notice World ID contract on Sepolia (use MockWorldId for testnet)
    /// @dev Set via env var WORLD_ID_ADDRESS, or defaults to deploying a mock
    address public worldIdAddress;

    // ================================================================
    //                    DEPLOYED ADDRESSES
    // ================================================================

    WorldIdGate public worldIdGate;
    RiskRegistry public riskRegistry;
    StrategyRouter public strategyRouter;
    AegisVault public aegisVault;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("=== AEGIS Protocol Deployment ===");
        console2.log("Deployer:", deployer);
        console2.log("Chain ID:", block.chainid);
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);

        // ============================================================
        // Step 1: Deploy WorldIdGate
        // ============================================================
        worldIdAddress = vm.envOr("WORLD_ID_ADDRESS", address(0));
        if (worldIdAddress == address(0)) {
            // Deploy mock for testnet
            console2.log("No WORLD_ID_ADDRESS set, deploying MockWorldId...");
            bytes memory mockCode = type(MockWorldIdDeploy).creationCode;
            address mockAddr;
            assembly {
                mockAddr := create(0, add(mockCode, 0x20), mload(mockCode))
            }
            worldIdAddress = mockAddr;
            console2.log("MockWorldId deployed at:", worldIdAddress);
        }

        worldIdGate = new WorldIdGate(
            worldIdAddress,   // IWorldID contract
            1,                // groupId (Orb verification)
            "aegis-vault",    // actionId
            24 hours          // verification TTL
        );
        console2.log("WorldIdGate deployed at:", address(worldIdGate));

        // ============================================================
        // Step 2: Deploy RiskRegistry
        // ============================================================
        riskRegistry = new RiskRegistry();
        console2.log("RiskRegistry deployed at:", address(riskRegistry));

        // ============================================================
        // Step 3: Deploy StrategyRouter
        // ============================================================
        strategyRouter = new StrategyRouter(SEPOLIA_CCIP_ROUTER);
        console2.log("StrategyRouter deployed at:", address(strategyRouter));

        // ============================================================
        // Step 4: Deploy AegisVault (in locked state - initialSetupComplete = false)
        // ============================================================
        aegisVault = new AegisVault(SEPOLIA_FORWARDER);
        console2.log("AegisVault deployed at:", address(aegisVault));

        // ============================================================
        // Step 5: Configure cross-references
        // ============================================================
        console2.log("");
        console2.log("=== Configuring Cross-References ===");

        // AegisVault references
        aegisVault.setRiskRegistry(address(riskRegistry));
        aegisVault.setStrategyRouter(address(strategyRouter));
        aegisVault.setWorldIdGate(address(worldIdGate));
        console2.log("AegisVault: registry, router, gate set");

        // RiskRegistry: register vault and authorize sentinel
        riskRegistry.registerVault(address(aegisVault));
        console2.log("RiskRegistry: vault registered");

        // StrategyRouter: set vault and risk registry
        strategyRouter.setVault(address(aegisVault));
        strategyRouter.setRiskRegistry(address(riskRegistry));
        console2.log("StrategyRouter: vault and registry set");

        // WorldIdGate: register vault
        worldIdGate.registerVault(address(aegisVault));
        console2.log("WorldIdGate: vault registered");

        // ============================================================
        // Step 6: Configure CCIP chains
        // ============================================================
        strategyRouter.setAllowedChain(SEPOLIA_CHAIN_SELECTOR, true);
        strategyRouter.setAllowedChain(BASE_SEPOLIA_CHAIN_SELECTOR, true);
        console2.log("StrategyRouter: Sepolia + Base Sepolia chains allowed");

        // ============================================================
        // Step 7: Add default protocol to RiskRegistry
        // ============================================================
        // Aave V3 Sepolia Pool (example - update with real address)
        address aavePool = vm.envOr("AAVE_POOL_ADDRESS", address(0xBE5E5728dB7F0E23E20B87E3737445796b272484));
        riskRegistry.addProtocol(aavePool, "Aave V3 Sepolia");
        console2.log("RiskRegistry: Aave V3 protocol added");

        // ============================================================
        // Step 8: Complete initial setup (enables user operations)
        // ============================================================
        aegisVault.completeInitialSetup();
        console2.log("AegisVault: initial setup completed");

        vm.stopBroadcast();

        // ============================================================
        // Summary
        // ============================================================
        console2.log("");
        console2.log("=== Deployment Complete ===");
        console2.log("WorldIdGate:    ", address(worldIdGate));
        console2.log("RiskRegistry:   ", address(riskRegistry));
        console2.log("StrategyRouter: ", address(strategyRouter));
        console2.log("AegisVault:     ", address(aegisVault));
        console2.log("WorldId Mock:   ", worldIdAddress);
        console2.log("Forwarder:      ", SEPOLIA_FORWARDER);
        console2.log("CCIP Router:    ", SEPOLIA_CCIP_ROUTER);
        console2.log("");
        console2.log("NEXT STEPS:");
        console2.log("1. Set workflow prefixes: forge script script/ConfigureVault.s.sol ...");
        console2.log("2. Update workflow configs with deployed addresses");
        console2.log("3. Deploy CRE workflows: cre workflow deploy --target staging-settings");
    }
}

/// @notice Minimal mock for testnet deployment when no real World ID contract exists
contract MockWorldIdDeploy {
    function verifyProof(
        uint256, uint256, uint256, uint256, uint256, uint256[8] calldata
    ) external pure {
        // Accept all proofs on testnet
    }
}
