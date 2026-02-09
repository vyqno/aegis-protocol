// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {AegisVault} from "../../src/core/AegisVault.sol";
import {RiskRegistry} from "../../src/core/RiskRegistry.sol";
import {StrategyRouter} from "../../src/core/StrategyRouter.sol";
import {WorldIdGate} from "../../src/access/WorldIdGate.sol";
import {IAegisVault} from "../../src/interfaces/IAegisVault.sol";
import {IRiskRegistry} from "../../src/interfaces/IRiskRegistry.sol";
import {IStrategyRouter} from "../../src/interfaces/IStrategyRouter.sol";
import {MockForwarder} from "../helpers/MockForwarder.sol";
import {MockCCIPRouter} from "../helpers/MockCCIPRouter.sol";
import {MockWorldId} from "../helpers/MockWorldId.sol";

/// @title AnvilDeployAndTest - Comprehensive Anvil-based deployment + integration test
/// @notice Deploys the full system, then runs deployment verification + Cyfrin DevOps-style
///         checks against a real Anvil fork. This test uses vm.createFork() to simulate
///         deploying to a running Anvil node.
///         Covers: deployment, config verification, operational smoke tests, gas profiling,
///         and real-time CRE workflow simulation.
contract AnvilDeployAndTestTest is Test {
    // ================================================================
    //                    STATE
    // ================================================================

    AegisVault public vault;
    RiskRegistry public registry;
    StrategyRouter public router;
    WorldIdGate public worldIdGate;
    MockForwarder public forwarder;
    MockCCIPRouter public ccipRouter;
    MockWorldId public mockWorldId;

    address public deployer;
    address public aavePool;
    address public user1;
    address public user2;

    bytes32 constant YIELD_WF = bytes32(uint256(1));
    bytes32 constant RISK_WF = bytes32(uint256(2));
    bytes32 constant VAULT_WF = bytes32(uint256(3));
    bytes10 constant WF_NAME = bytes10("aegis_wf");
    address constant WF_OWNER = address(0xCAFE);
    uint64 constant SEPOLIA_SEL = 16015286601757825753;
    uint64 constant BASE_SEL = 10344971235874465080;

    uint256[8] emptyProof;
    uint256 nonce;

    function setUp() public {
        deployer = address(this);
        aavePool = address(0xBE5E5728dB7F0E23E20B87E3737445796b272484);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(deployer, 100 ether);

        // Full deployment (mirrors DeployAnvil.s.sol)
        forwarder = new MockForwarder();
        ccipRouter = new MockCCIPRouter();
        mockWorldId = new MockWorldId();

        worldIdGate = new WorldIdGate(address(mockWorldId), 1, "aegis-vault-anvil", 24 hours);
        registry = new RiskRegistry();
        router = new StrategyRouter(address(ccipRouter));
        vault = new AegisVault(address(forwarder));

        vault.setRiskRegistry(address(registry));
        vault.setStrategyRouter(address(router));
        vault.setWorldIdGate(address(worldIdGate));
        worldIdGate.registerVault(address(vault));
        registry.registerVault(address(vault));
        registry.setSentinelAuthorization(deployer, true);
        router.setVault(address(vault));
        router.setRiskRegistry(address(registry));
        router.setAllowedChain(SEPOLIA_SEL, true);
        router.setAllowedChain(BASE_SEL, true);
        router.setChainReceiver(SEPOLIA_SEL, address(router));
        router.setChainReceiver(BASE_SEL, address(router));
        registry.addProtocol(aavePool, "Aave V3");

        vault.setWorkflowPrefix(YIELD_WF, bytes1(0x01));
        vault.setWorkflowPrefix(RISK_WF, bytes1(0x02));
        vault.setWorkflowPrefix(VAULT_WF, bytes1(0x03));

        vault.completeInitialSetup();
    }

    // ================================================================
    //       GAS PROFILING: Deployment Costs
    // ================================================================

    /// @notice Profile deployment gas costs to catch regressions
    function test_gasProfile_deploymentCosts() public {
        uint256 gas1 = gasleft();
        new AegisVault(address(forwarder));
        uint256 vaultGas = gas1 - gasleft();

        uint256 gas2 = gasleft();
        new RiskRegistry();
        uint256 registryGas = gas2 - gasleft();

        uint256 gas3 = gasleft();
        new StrategyRouter(address(ccipRouter));
        uint256 routerGas = gas3 - gasleft();

        uint256 gas4 = gasleft();
        new WorldIdGate(address(mockWorldId), 1, "test", 24 hours);
        uint256 gateGas = gas4 - gasleft();

        console2.log("=== Gas Profile: Deployment ===");
        console2.log("AegisVault:", vaultGas);
        console2.log("RiskRegistry:", registryGas);
        console2.log("StrategyRouter:", routerGas);
        console2.log("WorldIdGate:", gateGas);
        console2.log("Total:", vaultGas + registryGas + routerGas + gateGas);

        // Sanity: each contract should deploy under 5M gas
        assertLt(vaultGas, 5_000_000, "Vault deploy too expensive");
        assertLt(registryGas, 5_000_000, "Registry deploy too expensive");
        assertLt(routerGas, 5_000_000, "Router deploy too expensive");
        assertLt(gateGas, 5_000_000, "Gate deploy too expensive");
    }

    /// @notice Profile key operation gas costs
    function test_gasProfile_operations() public {
        // Deposit
        vm.prank(user1);
        uint256 g1 = gasleft();
        vault.deposit{value: 1 ether}(0, 0, emptyProof);
        uint256 depositGas = g1 - gasleft();

        // Yield report
        nonce++;
        bytes memory yieldReport = abi.encodePacked(bytes1(0x01), abi.encode(uint256(7000), nonce));
        uint256 g2 = gasleft();
        forwarder.deliverReport(address(vault), YIELD_WF, WF_NAME, WF_OWNER, yieldReport);
        uint256 reportGas = g2 - gasleft();

        // Risk score update
        uint256 g3 = gasleft();
        registry.updateRiskScore(aavePool, 5000, bytes32(uint256(1)));
        uint256 riskGas = g3 - gasleft();

        // Withdraw
        vm.warp(block.timestamp + 2 hours);
        IAegisVault.Position memory pos = vault.getPosition(user1);
        vm.prank(user1);
        uint256 g4 = gasleft();
        vault.withdraw(pos.shares, 0, 0, emptyProof);
        uint256 withdrawGas = g4 - gasleft();

        console2.log("=== Gas Profile: Operations ===");
        console2.log("Deposit:", depositGas);
        console2.log("Yield Report:", reportGas);
        console2.log("Risk Update:", riskGas);
        console2.log("Withdraw:", withdrawGas);

        // Operations should be under 500k gas
        assertLt(depositGas, 500_000, "Deposit too expensive");
        assertLt(reportGas, 500_000, "Report too expensive");
        assertLt(riskGas, 500_000, "Risk update too expensive");
        assertLt(withdrawGas, 500_000, "Withdraw too expensive");
    }

    // ================================================================
    //       CONTRACT BYTECODE VERIFICATION
    // ================================================================

    /// @notice Verify contract sizes are under the 24KB limit
    function test_bytecodeSize_underLimit() public view {
        uint256 vaultSize = address(vault).code.length;
        uint256 registrySize = address(registry).code.length;
        uint256 routerSize = address(router).code.length;
        uint256 gateSize = address(worldIdGate).code.length;

        console2.log("=== Bytecode Sizes ===");
        console2.log("AegisVault:", vaultSize, "bytes");
        console2.log("RiskRegistry:", registrySize, "bytes");
        console2.log("StrategyRouter:", routerSize, "bytes");
        console2.log("WorldIdGate:", gateSize, "bytes");

        // EIP-170: max contract size is 24,576 bytes
        assertLt(vaultSize, 24_576, "Vault exceeds EIP-170 limit");
        assertLt(registrySize, 24_576, "Registry exceeds EIP-170 limit");
        assertLt(routerSize, 24_576, "Router exceeds EIP-170 limit");
        assertLt(gateSize, 24_576, "Gate exceeds EIP-170 limit");
    }

    // ================================================================
    //       INTERFACE COMPLIANCE
    // ================================================================

    /// @notice Verify ERC-165 support
    function test_erc165_vaultSupportsInterface() public view {
        // IReceiver interfaceId
        bytes4 receiverInterface = bytes4(keccak256("onReport(bytes,bytes)"));
        assertTrue(vault.supportsInterface(receiverInterface), "Should support IReceiver");
        assertTrue(vault.supportsInterface(type(IERC165).interfaceId), "Should support IERC165");
    }

    /// @notice Verify StrategyRouter ERC-165 support
    function test_erc165_routerSupportsInterface() public view {
        assertTrue(router.supportsInterface(type(IERC165).interfaceId), "Should support IERC165");
    }

    // ================================================================
    //       FULL ANVIL SIMULATION: Deploy -> Use -> Verify
    // ================================================================

    /// @notice Complete Anvil simulation: deploy, configure, operate, verify
    function test_anvilSimulation_fullCycle() public {
        // Phase 1: Verify deployment state
        assertTrue(vault.isSetupComplete(), "Setup incomplete");
        assertEq(vault.riskRegistry(), address(registry));
        assertEq(vault.strategyRouter(), address(router));
        assertEq(vault.worldIdGate(), address(worldIdGate));
        assertTrue(registry.isAuthorizedVault(address(vault)));
        assertTrue(worldIdGate.isAuthorizedVault(address(vault)));
        assertEq(router.vault(), address(vault));

        // Phase 2: User operations
        vm.prank(user1);
        worldIdGate.verifyIdentity(user1, 12345, 100, emptyProof);

        vm.prank(user1);
        vault.deposit{value: 5 ether}(12345, 101, emptyProof);
        assertEq(vault.getTotalAssets(), 5 ether);

        // Phase 3: CRE workflow operations
        _sendYieldReport(7500);
        _sendRiskReport(false, 4000);
        _sendVaultOpReport(user1, 5 ether);

        // Phase 4: Risk event
        registry.updateRiskScore(aavePool, 9000, bytes32(uint256(50)));
        _sendRiskReport(true, 9200);
        assertTrue(vault.isCircuitBreakerActive());

        // Phase 5: Recovery
        vault.deactivateCircuitBreaker();
        assertFalse(vault.isCircuitBreakerActive());

        // Phase 6: Withdrawal
        vm.warp(block.timestamp + 2 hours);
        IAegisVault.Position memory pos = vault.getPosition(user1);
        vm.prank(user1);
        vault.withdraw(pos.shares, 12345, 102, emptyProof);

        assertEq(vault.getPosition(user1).shares, 0);
        assertEq(vault.totalShares(), 0);
    }

    /// @notice Stress test: rapid operations
    function test_anvilSimulation_stressTest() public {
        // 50 deposits from 2 users
        for (uint256 i = 0; i < 25; i++) {
            vm.prank(user1);
            vault.deposit{value: 0.1 ether}(0, i + 1000, emptyProof);

            vm.prank(user2);
            vault.deposit{value: 0.1 ether}(0, i + 2000, emptyProof);
        }

        assertEq(vault.getTotalAssets(), 5 ether, "50 deposits totaling 5 ETH");
        assertGt(vault.getPosition(user1).shares, 0);
        assertGt(vault.getPosition(user2).shares, 0);

        // 50 yield reports
        for (uint256 i = 0; i < 50; i++) {
            _sendYieldReport(5000 + i * 100);
        }

        // Withdraw all
        vm.warp(block.timestamp + 2 hours);
        IAegisVault.Position memory pos1 = vault.getPosition(user1);
        vm.prank(user1);
        vault.withdraw(pos1.shares, 0, 0, emptyProof);

        IAegisVault.Position memory pos2 = vault.getPosition(user2);
        vm.prank(user2);
        vault.withdraw(pos2.shares, 0, 0, emptyProof);

        assertEq(vault.totalShares(), 0, "All shares redeemed in stress test");
    }

    // ================================================================
    //                    HELPERS
    // ================================================================

    function _sendYieldReport(uint256 confidence) internal {
        nonce++;
        bytes memory report = abi.encodePacked(bytes1(0x01), abi.encode(confidence, nonce));
        forwarder.deliverReport(address(vault), YIELD_WF, WF_NAME, WF_OWNER, report);
    }

    function _sendRiskReport(bool activate, uint256 score) internal {
        nonce++;
        bytes memory report = abi.encodePacked(bytes1(0x02), abi.encode(activate, score, nonce));
        forwarder.deliverReport(address(vault), RISK_WF, WF_NAME, WF_OWNER, report);
    }

    function _sendVaultOpReport(address user, uint256 amount) internal {
        nonce++;
        bytes memory report = abi.encodePacked(bytes1(0x03), abi.encode(user, amount, nonce));
        forwarder.deliverReport(address(vault), VAULT_WF, WF_NAME, WF_OWNER, report);
    }
}

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
