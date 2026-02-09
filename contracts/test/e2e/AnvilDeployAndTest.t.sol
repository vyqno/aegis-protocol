// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {DevOpsTools} from "@foundry-devops/DevOpsTools.sol";
import {AegisVault} from "../../src/core/AegisVault.sol";
import {RiskRegistry} from "../../src/core/RiskRegistry.sol";
import {StrategyRouter} from "../../src/core/StrategyRouter.sol";
import {WorldIdGate} from "../../src/access/WorldIdGate.sol";
import {IAegisVault} from "../../src/interfaces/IAegisVault.sol";

/// @title AnvilDeployAndTest - Post-deployment integration tests against LIVE Anvil contracts
/// @notice Uses DevOpsTools.get_most_recent_deployment() to fetch real deployed addresses
///         from broadcast artifacts, then runs gas profiling, bytecode checks, stress tests,
///         and full lifecycle simulations against the LIVE contracts on Anvil.
/// @dev Usage:
///      1. Start Anvil:  anvil --port 8545
///      2. Deploy:       forge script script/DeployAnvil.s.sol --tc DeployAnvil --rpc-url http://127.0.0.1:8545 --broadcast
///      3. Test:         forge test --match-contract AnvilDeployAndTestTest --fork-url http://127.0.0.1:8545
contract AnvilDeployAndTestTest is Test {
    // ================================================================
    //     LIVE CONTRACT INSTANCES (fetched from broadcast artifacts)
    // ================================================================

    AegisVault public vault;
    RiskRegistry public registry;
    StrategyRouter public router;
    WorldIdGate public worldIdGate;

    address public deployer;
    address public forwarderAddr;
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

    /// @notice Fetch deployed addresses from broadcast artifacts — NO new deployments
    function setUp() public {
        vault = AegisVault(
            payable(DevOpsTools.get_most_recent_deployment("AegisVault", block.chainid))
        );
        registry = RiskRegistry(
            DevOpsTools.get_most_recent_deployment("RiskRegistry", block.chainid)
        );
        router = StrategyRouter(
            payable(DevOpsTools.get_most_recent_deployment("StrategyRouter", block.chainid))
        );
        worldIdGate = WorldIdGate(
            DevOpsTools.get_most_recent_deployment("WorldIdGate", block.chainid)
        );

        deployer = vault.owner();
        forwarderAddr = vault.getForwarderAddress();
        aavePool = address(0xBE5E5728dB7F0E23E20B87E3737445796b272484);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(deployer, 100 ether);
    }

    // ================================================================
    //       GAS PROFILING: Operation Costs (against LIVE contracts)
    // ================================================================

    function test_gasProfile_operations() public {
        // Deposit
        vm.prank(user1);
        uint256 g1 = gasleft();
        vault.deposit{value: 1 ether}(0, 0, emptyProof);
        uint256 depositGas = g1 - gasleft();

        // Yield report via real forwarder
        nonce++;
        bytes memory yieldReport = abi.encodePacked(bytes1(0x01), abi.encode(uint256(7000), nonce));
        uint256 g2 = gasleft();
        _deliverReport(YIELD_WF, yieldReport);
        uint256 reportGas = g2 - gasleft();

        // Risk score update
        uint256 g3 = gasleft();
        vm.prank(deployer);
        registry.updateRiskScore(aavePool, 5000, bytes32(uint256(1)));
        uint256 riskGas = g3 - gasleft();

        // Withdraw
        vm.warp(block.timestamp + 2 hours);
        IAegisVault.Position memory pos = vault.getPosition(user1);
        vm.prank(user1);
        uint256 g4 = gasleft();
        vault.withdraw(pos.shares, 0, 0, emptyProof);
        uint256 withdrawGas = g4 - gasleft();

        console2.log("=== Gas Profile: Live Contract Operations ===");
        console2.log("Deposit:", depositGas);
        console2.log("Yield Report:", reportGas);
        console2.log("Risk Update:", riskGas);
        console2.log("Withdraw:", withdrawGas);

        assertLt(depositGas, 500_000, "Deposit too expensive");
        assertLt(reportGas, 500_000, "Report too expensive");
        assertLt(riskGas, 500_000, "Risk update too expensive");
        assertLt(withdrawGas, 500_000, "Withdraw too expensive");
    }

    // ================================================================
    //       CONTRACT BYTECODE VERIFICATION (LIVE bytecode)
    // ================================================================

    function test_bytecodeSize_underLimit() public view {
        uint256 vaultSize = address(vault).code.length;
        uint256 registrySize = address(registry).code.length;
        uint256 routerSize = address(router).code.length;
        uint256 gateSize = address(worldIdGate).code.length;

        console2.log("=== Live Contract Bytecode Sizes ===");
        console2.log("AegisVault:", vaultSize, "bytes");
        console2.log("RiskRegistry:", registrySize, "bytes");
        console2.log("StrategyRouter:", routerSize, "bytes");
        console2.log("WorldIdGate:", gateSize, "bytes");

        assertLt(vaultSize, 24_576, "Vault exceeds EIP-170 limit");
        assertLt(registrySize, 24_576, "Registry exceeds EIP-170 limit");
        assertLt(routerSize, 24_576, "Router exceeds EIP-170 limit");
        assertLt(gateSize, 24_576, "Gate exceeds EIP-170 limit");
    }

    // ================================================================
    //       INTERFACE COMPLIANCE (LIVE contracts)
    // ================================================================

    function test_erc165_vaultSupportsInterface() public view {
        bytes4 receiverInterface = bytes4(keccak256("onReport(bytes,bytes)"));
        assertTrue(vault.supportsInterface(receiverInterface), "Should support IReceiver");
        assertTrue(vault.supportsInterface(type(IERC165).interfaceId), "Should support IERC165");
    }

    function test_erc165_routerSupportsInterface() public view {
        assertTrue(router.supportsInterface(type(IERC165).interfaceId), "Should support IERC165");
    }

    // ================================================================
    //       FULL LIFECYCLE: Deploy -> Operate -> Verify (LIVE)
    // ================================================================

    function test_anvilSimulation_fullCycle() public {
        // Phase 1: Verify live deployment state
        assertTrue(vault.isSetupComplete(), "Setup incomplete");
        assertEq(vault.riskRegistry(), address(registry));
        assertEq(vault.strategyRouter(), address(router));
        assertEq(vault.worldIdGate(), address(worldIdGate));
        assertTrue(registry.isAuthorizedVault(address(vault)));
        assertTrue(worldIdGate.isAuthorizedVault(address(vault)));
        assertEq(router.vault(), address(vault));

        // Phase 2: User deposit on live vault
        vm.prank(user1);
        vault.deposit{value: 5 ether}(0, 0, emptyProof);
        assertEq(vault.getTotalAssets(), 5 ether);

        // Phase 3: CRE workflow reports via real forwarder address
        _sendYieldReport(7500);
        _sendRiskReport(false, 4000);
        _sendVaultOpReport(user1, 5 ether);

        // Phase 4: Risk event on live registry
        vm.prank(deployer);
        registry.updateRiskScore(aavePool, 9000, bytes32(uint256(50)));
        _sendRiskReport(true, 9200);
        assertTrue(vault.isCircuitBreakerActive());

        // Phase 5: Recovery
        vm.prank(deployer);
        vault.deactivateCircuitBreaker();
        assertFalse(vault.isCircuitBreakerActive());

        // Phase 6: Withdrawal from live vault
        vm.warp(block.timestamp + 2 hours);
        IAegisVault.Position memory pos = vault.getPosition(user1);
        vm.prank(user1);
        vault.withdraw(pos.shares, 0, 0, emptyProof);

        assertEq(vault.getPosition(user1).shares, 0);
        assertEq(vault.totalShares(), 0);
    }

    /// @notice Stress test: rapid operations against live contracts
    /// @dev Kept small (10 ops) since each is a real RPC call on fork
    function test_anvilSimulation_stressTest() public {
        // 10 deposits from 2 users on the live vault
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(user1);
            vault.deposit{value: 0.1 ether}(0, i + 1000, emptyProof);

            vm.prank(user2);
            vault.deposit{value: 0.1 ether}(0, i + 2000, emptyProof);
        }

        assertEq(vault.getTotalAssets(), 1 ether, "10 deposits totaling 1 ETH");
        assertGt(vault.getPosition(user1).shares, 0);
        assertGt(vault.getPosition(user2).shares, 0);

        // 5 yield reports via real forwarder
        for (uint256 i = 0; i < 5; i++) {
            _sendYieldReport(5000 + i * 100);
        }

        // Withdraw all from live vault
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

    /// @notice Deliver a report by pranking as the REAL deployed forwarder
    function _deliverReport(bytes32 workflowId, bytes memory report) internal {
        bytes memory metadata = abi.encodePacked(workflowId, WF_NAME, WF_OWNER);
        vm.prank(forwarderAddr);
        vault.onReport(metadata, report);
    }

    function _sendYieldReport(uint256 confidence) internal {
        nonce++;
        bytes memory report = abi.encodePacked(bytes1(0x01), abi.encode(confidence, nonce));
        _deliverReport(YIELD_WF, report);
    }

    function _sendRiskReport(bool activate, uint256 score) internal {
        nonce++;
        bytes memory report = abi.encodePacked(bytes1(0x02), abi.encode(activate, score, nonce));
        _deliverReport(RISK_WF, report);
    }

    function _sendVaultOpReport(address user, uint256 amount) internal {
        nonce++;
        bytes memory report = abi.encodePacked(bytes1(0x03), abi.encode(user, amount, nonce));
        _deliverReport(VAULT_WF, report);
    }
}
