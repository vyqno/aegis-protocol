// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {AegisVault} from "../src/core/AegisVault.sol";
import {RiskRegistry} from "../src/core/RiskRegistry.sol";
import {StrategyRouter} from "../src/core/StrategyRouter.sol";
import {WorldIdGate} from "../src/access/WorldIdGate.sol";

/// @title DeployAnvil - Deterministic deployment script for local Anvil testing
/// @notice Deploys the full AEGIS protocol to a local Anvil instance, wires all
///         cross-references, and leaves the system in a fully operational state.
///         Used by Cyfrin DevOps tests to verify deployment artifacts.
/// @dev Run: forge script script/DeployAnvil.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
contract DeployAnvil is Script {
    // Anvil default account #0 private key
    uint256 constant ANVIL_DEFAULT_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    // Mock addresses for Anvil
    address constant MOCK_FORWARDER = address(0x1111111111111111111111111111111111111111);
    address constant MOCK_CCIP_ROUTER_PLACEHOLDER = address(0x2222222222222222222222222222222222222222);

    // CCIP chain selectors (same as production)
    uint64 constant SEPOLIA_CHAIN_SELECTOR = 16015286601757825753;
    uint64 constant BASE_SEPOLIA_CHAIN_SELECTOR = 10344971235874465080;

    // Deployed contract references
    AegisVault public aegisVault;
    RiskRegistry public riskRegistry;
    StrategyRouter public strategyRouter;
    WorldIdGate public worldIdGate;
    address public mockWorldIdAddr;
    address public mockCCIPRouterAddr;
    address public mockForwarderAddr;

    function run() external {
        vm.startBroadcast(ANVIL_DEFAULT_KEY);

        address deployer = vm.addr(ANVIL_DEFAULT_KEY);
        console2.log("=== AEGIS Anvil Deployment ===");
        console2.log("Deployer:", deployer);

        // Step 1: Deploy mock infrastructure
        MockWorldIdAnvil mockWorldId = new MockWorldIdAnvil();
        mockWorldIdAddr = address(mockWorldId);

        MockCCIPRouterAnvil mockCCIP = new MockCCIPRouterAnvil();
        mockCCIPRouterAddr = address(mockCCIP);

        MockForwarderAnvil mockFwd = new MockForwarderAnvil();
        mockForwarderAddr = address(mockFwd);

        console2.log("MockWorldId:", mockWorldIdAddr);
        console2.log("MockCCIPRouter:", mockCCIPRouterAddr);
        console2.log("MockForwarder:", mockForwarderAddr);

        // Step 2: Deploy core contracts
        worldIdGate = new WorldIdGate(
            mockWorldIdAddr,
            1,
            "aegis-vault-anvil",
            24 hours
        );
        console2.log("WorldIdGate:", address(worldIdGate));

        riskRegistry = new RiskRegistry();
        console2.log("RiskRegistry:", address(riskRegistry));

        strategyRouter = new StrategyRouter(mockCCIPRouterAddr);
        console2.log("StrategyRouter:", address(strategyRouter));

        aegisVault = new AegisVault(mockForwarderAddr);
        console2.log("AegisVault:", address(aegisVault));

        // Step 3: Wire cross-references
        aegisVault.setRiskRegistry(address(riskRegistry));
        aegisVault.setStrategyRouter(address(strategyRouter));
        aegisVault.setWorldIdGate(address(worldIdGate));

        // Step 4: Configure authorization
        worldIdGate.registerVault(address(aegisVault));
        riskRegistry.registerVault(address(aegisVault));
        riskRegistry.setSentinelAuthorization(deployer, true);

        strategyRouter.setVault(address(aegisVault));
        strategyRouter.setRiskRegistry(address(riskRegistry));

        // Step 5: Configure CCIP chains
        strategyRouter.setAllowedChain(SEPOLIA_CHAIN_SELECTOR, true);
        strategyRouter.setAllowedChain(BASE_SEPOLIA_CHAIN_SELECTOR, true);
        strategyRouter.setChainReceiver(SEPOLIA_CHAIN_SELECTOR, address(strategyRouter));
        strategyRouter.setChainReceiver(BASE_SEPOLIA_CHAIN_SELECTOR, address(strategyRouter));

        // Step 6: Add default protocol
        address aavePool = address(0xBE5E5728dB7F0E23E20B87E3737445796b272484);
        riskRegistry.addProtocol(aavePool, "Aave V3 Anvil");

        // Step 7: Bind workflow prefixes
        aegisVault.setWorkflowPrefix(bytes32(uint256(1)), bytes1(0x01)); // yield
        aegisVault.setWorkflowPrefix(bytes32(uint256(2)), bytes1(0x02)); // risk
        aegisVault.setWorkflowPrefix(bytes32(uint256(3)), bytes1(0x03)); // vault-op

        // Step 8: Complete setup
        aegisVault.completeInitialSetup();

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== Deployment Complete (Anvil) ===");
        console2.log("All contracts deployed and wired.");
        console2.log("Vault is setup-complete and ready for deposits.");
    }
}

/// @notice Minimal mock World ID for Anvil deployment
contract MockWorldIdAnvil {
    function verifyProof(
        uint256, uint256, uint256, uint256, uint256, uint256[8] calldata
    ) external pure {}
}

/// @notice Minimal mock CCIP Router for Anvil deployment
contract MockCCIPRouterAnvil {
    uint256 private _counter;

    function isChainSupported(uint64) external pure returns (bool) { return true; }

    function getFee(uint64, bytes calldata) external pure returns (uint256) {
        return 0.001 ether;
    }

    // Simplified getFee for Client.EVM2AnyMessage - uses fallback
    fallback() external payable {
        // Accept any call (mock)
    }

    receive() external payable {}
}

/// @notice Minimal mock KeystoneForwarder for Anvil deployment
contract MockForwarderAnvil {
    // Just needs to exist at a valid address
    receive() external payable {}
}
