// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {StrategyRouter} from "../src/core/StrategyRouter.sol";

/// @title DeployBase - Deploy StrategyRouter receiver on Base Sepolia for CCIP
/// @notice Only deploys a StrategyRouter instance on Base Sepolia to receive cross-chain messages
/// @dev Run: forge script script/DeployBase.s.sol --rpc-url $BASE_SEPOLIA_RPC --broadcast
contract DeployBase is Script {
    /// @notice CCIP Router on Base Sepolia
    address constant BASE_SEPOLIA_CCIP_ROUTER = 0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93;

    /// @notice CCIP chain selector for Ethereum Sepolia
    uint64 constant SEPOLIA_CHAIN_SELECTOR = 16015286601757825753;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Sepolia-deployed StrategyRouter address (must be set after Deploy.s.sol)
        address sepoliaRouter = vm.envAddress("SEPOLIA_STRATEGY_ROUTER");

        console2.log("=== AEGIS Base Sepolia Deployment ===");
        console2.log("Deployer:", deployer);
        console2.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy StrategyRouter on Base Sepolia
        StrategyRouter baseRouter = new StrategyRouter(BASE_SEPOLIA_CCIP_ROUTER);
        console2.log("Base StrategyRouter deployed at:", address(baseRouter));

        // Allow Sepolia chain for CCIP messages
        baseRouter.setAllowedChain(SEPOLIA_CHAIN_SELECTOR, true);

        // Set Sepolia router as allowed sender
        baseRouter.setChainReceiver(SEPOLIA_CHAIN_SELECTOR, sepoliaRouter);
        console2.log("Sepolia chain allowed, sender set to:", sepoliaRouter);

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== Base Sepolia Deployment Complete ===");
        console2.log("Base StrategyRouter:", address(baseRouter));
        console2.log("");
        console2.log("NEXT: On Sepolia, set Base receiver:");
        console2.log("  strategyRouter.setChainReceiver(BASE_CHAIN_SELECTOR, <base_router_addr>)");
    }
}
