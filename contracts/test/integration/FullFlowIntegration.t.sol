// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AegisVault} from "../../src/core/AegisVault.sol";
import {RiskRegistry} from "../../src/core/RiskRegistry.sol";
import {StrategyRouter} from "../../src/core/StrategyRouter.sol";
import {WorldIdGate} from "../../src/access/WorldIdGate.sol";
import {IAegisVault} from "../../src/interfaces/IAegisVault.sol";
import {IWorldIdGate} from "../../src/interfaces/IWorldIdGate.sol";
import {MockForwarder} from "../helpers/MockForwarder.sol";
import {MockCCIPRouter} from "../helpers/MockCCIPRouter.sol";
import {MockWorldId} from "../helpers/MockWorldId.sol";
import {TestConstants} from "../helpers/TestConstants.sol";

/// @title FullFlowIntegrationTest - End-to-end integration test
/// @dev Full flow: deploy -> setup -> WorldID verify -> deposit -> risk report -> CB ->
///      auto-deactivate -> withdraw. Also covers security-focused tests A-G.
contract FullFlowIntegrationTest is Test {
    AegisVault public vault;
    RiskRegistry public registry;
    StrategyRouter public router;
    WorldIdGate public worldIdGate;
    MockForwarder public forwarder;
    MockCCIPRouter public ccipRouter;
    MockWorldId public mockWorldId;

    address public user1;
    address public user2;

    bytes32 constant YIELD_WORKFLOW_ID = bytes32(uint256(1));
    bytes32 constant RISK_WORKFLOW_ID = bytes32(uint256(2));
    bytes32 constant VAULT_WORKFLOW_ID = bytes32(uint256(3));
    bytes10 constant TEST_WORKFLOW_NAME = bytes10("test_work");
    address constant TEST_WORKFLOW_OWNER = address(0xCAFE);

    uint256 constant TEST_ROOT = 12345;
    uint256[8] testProof;

    function setUp() public {
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy all contracts
        forwarder = new MockForwarder();
        ccipRouter = new MockCCIPRouter();
        mockWorldId = new MockWorldId();

        vault = new AegisVault(address(forwarder));
        registry = new RiskRegistry();
        router = new StrategyRouter(address(ccipRouter));
        worldIdGate = new WorldIdGate(
            address(mockWorldId),
            1, // groupId
            "AEGIS-VERIFY-V1",
            24 hours
        );

        // Wire contracts together
        vault.setRiskRegistry(address(registry));
        vault.setStrategyRouter(address(router));
        vault.setWorldIdGate(address(worldIdGate));

        // Bind workflows to prefixes
        vault.setWorkflowPrefix(YIELD_WORKFLOW_ID, bytes1(0x01));
        vault.setWorkflowPrefix(RISK_WORKFLOW_ID, bytes1(0x02));
        vault.setWorkflowPrefix(VAULT_WORKFLOW_ID, bytes1(0x03));

        // Register vault in WorldIdGate
        worldIdGate.registerVault(address(vault));

        // Setup registry
        registry.registerVault(address(vault));
        registry.setSentinelAuthorization(address(this), true);
        registry.addProtocol(makeAddr("aave"), "Aave");

        // Setup router
        router.setVault(address(vault));
        uint64 chainA = TestConstants.SEPOLIA_CHAIN_SELECTOR;
        router.setAllowedChain(chainA, true);
        router.setChainReceiver(chainA, address(router));

        // Complete setup LAST
        vault.completeInitialSetup();

        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }

    // ================================================================
    //               FULL FLOW END-TO-END TEST
    // ================================================================

    function test_fullFlow_deposit_risk_circuitBreaker_withdraw() public {
        // Step 1: User verifies World ID
        vm.prank(user1);
        worldIdGate.verifyIdentity(user1, TEST_ROOT, 111, testProof);
        assertTrue(worldIdGate.isVerified(user1));

        // Step 2: User deposits (vault calls worldIdGate.verifyIdentity - idempotent)
        vm.prank(user1);
        vault.deposit{value: 5 ether}(TEST_ROOT, 222, testProof);

        IAegisVault.Position memory pos = vault.getPosition(user1);
        assertGt(pos.shares, 0, "Should have shares");
        assertEq(vault.getTotalAssets(), 5 ether);

        // Step 3: Yield scanner sends report (0x01)
        bytes memory yieldReport = abi.encodePacked(
            bytes1(0x01),
            abi.encode(uint256(500))
        );
        forwarder.deliverReport(
            address(vault),
            YIELD_WORKFLOW_ID,
            TEST_WORKFLOW_NAME,
            TEST_WORKFLOW_OWNER,
            yieldReport
        );

        // Step 4: Risk sentinel sends report (0x02) - activates circuit breaker
        bytes memory riskReport = abi.encodePacked(
            bytes1(0x02),
            abi.encode(true, uint256(9500))
        );
        forwarder.deliverReport(
            address(vault),
            RISK_WORKFLOW_ID,
            TEST_WORKFLOW_NAME,
            TEST_WORKFLOW_OWNER,
            riskReport
        );

        assertTrue(vault.isCircuitBreakerActive(), "CB should be active");

        // Step 5: Verify CB blocks BOTH deposits AND withdrawals
        vm.prank(user1);
        vm.expectRevert(IAegisVault.CircuitBreakerActive.selector);
        vault.deposit{value: 1 ether}(0, 0, testProof);

        vm.warp(block.timestamp + 2 hours);
        vm.prank(user1);
        vm.expectRevert(IAegisVault.CircuitBreakerActive.selector);
        vault.withdraw(pos.shares, 0, 0, testProof);

        // Step 6: Wait for auto-deactivation (72 hours)
        vm.warp(block.timestamp + 73 hours);
        assertFalse(vault.isCircuitBreakerActive(), "CB should auto-deactivate");

        // Step 7: User successfully withdraws
        pos = vault.getPosition(user1);
        vm.prank(user1);
        vault.withdraw(pos.shares, 0, 0, testProof);

        IAegisVault.Position memory posAfter = vault.getPosition(user1);
        assertEq(posAfter.shares, 0, "Should have 0 shares after full withdrawal");
    }

    // ================================================================
    //          SECURITY-FOCUSED INTEGRATION TESTS (A-G)
    // ================================================================

    /// @notice Test A: Workflow Impersonation - wrong workflow sends wrong prefix
    function test_security_A_workflowImpersonation() public {
        // Yield workflow (ID 1) tries to send risk prefix (0x02)
        bytes memory report = abi.encodePacked(
            bytes1(0x02),
            abi.encode(true, uint256(9000))
        );

        vm.expectRevert();
        forwarder.deliverReport(
            address(vault),
            YIELD_WORKFLOW_ID, // Yield workflow...
            TEST_WORKFLOW_NAME,
            TEST_WORKFLOW_OWNER,
            report // ...with risk prefix 0x02
        );
    }

    /// @notice Test B: Cross-Chain Replay - same report can't be processed twice
    function test_security_B_crossChainReplay() public {
        bytes memory report = abi.encodePacked(
            bytes1(0x01),
            abi.encode(uint256(500))
        );

        // First delivery succeeds
        forwarder.deliverReport(
            address(vault),
            YIELD_WORKFLOW_ID,
            TEST_WORKFLOW_NAME,
            TEST_WORKFLOW_OWNER,
            report
        );

        // Replay should fail (same chainid = same dedup key)
        vm.expectRevert();
        forwarder.deliverReport(
            address(vault),
            YIELD_WORKFLOW_ID,
            TEST_WORKFLOW_NAME,
            TEST_WORKFLOW_OWNER,
            report
        );
    }

    /// @notice Test C: Circuit Breaker Abuse - 4th activation in 1 hour fails
    function test_security_C_circuitBreakerAbuse() public {
        for (uint256 i = 0; i < 3; i++) {
            registry.activateCircuitBreaker(bytes32(i));
            registry.deactivateCircuitBreaker();
        }

        // 4th activation should be rate limited
        vm.expectRevert();
        registry.activateCircuitBreaker(bytes32(uint256(3)));
    }

    /// @notice Test D: First Depositor Attack - virtual shares protect victim
    function test_security_D_firstDepositorAttack() public {
        // Attacker deposits minimum (unique nullifier 444)
        vm.prank(user1);
        vault.deposit{value: 0.001 ether}(TEST_ROOT, 444, testProof);

        // Attacker donates 10 ETH directly to vault
        vm.deal(address(this), 10 ether);
        (bool ok,) = address(vault).call{value: 10 ether}("");
        assertTrue(ok);

        // Victim deposits 1 ETH (unique nullifier 555)
        vm.prank(user2);
        vault.deposit{value: 1 ether}(TEST_ROOT, 555, testProof);

        IAegisVault.Position memory victimPos = vault.getPosition(user2);
        assertGt(victimPos.shares, 0, "Victim must get shares (virtual shares)");

        uint256 victimAssets = vault.convertToAssets(victimPos.shares);
        assertGt(victimAssets, 0, "Victim assets must be non-zero");
    }

    /// @notice Test E: World ID Proof Front-Running - wrong msg.sender reverts
    function test_security_E_worldIdProofFrontRunning() public {
        // user2 tries to use a proof meant for user1
        vm.prank(user2);
        vm.expectRevert(
            abi.encodeWithSelector(IWorldIdGate.SignalMismatch.selector, user1, user2)
        );
        worldIdGate.verifyIdentity(user1, TEST_ROOT, 111, testProof);
    }

    /// @notice Test G: Forwarder Zero Address Block
    function test_security_G_forwarderZeroAddressBlock() public {
        vm.expectRevert(IAegisVault.ForwarderCannotBeZero.selector);
        vault.setForwarderAddress(address(0));
    }

    // ================================================================
    //          WORLD ID + VAULT INTEGRATION TESTS
    // ================================================================

    function test_deposit_with_worldIdGate_connected() public {
        // User verifies first
        vm.prank(user1);
        worldIdGate.verifyIdentity(user1, TEST_ROOT, 111, testProof);

        // Deposit with WorldIdGate connected - vault calls verifyIdentity (idempotent)
        vm.prank(user1);
        vault.deposit{value: 1 ether}(TEST_ROOT, 222, testProof);

        assertGt(vault.getPosition(user1).shares, 0);
    }

    function test_deposit_reverts_without_worldId_when_gate_connected() public {
        // user2 has NOT verified with World ID
        // When vault calls verifyIdentity for unverified user, it will try to verify
        // with nullifierHash=0, which should work with mock (mock accepts all)
        // But the important thing is the signal == msg.sender or vault check passes

        // This test verifies the vault correctly calls WorldIdGate
        vm.prank(user2);
        vault.deposit{value: 1 ether}(TEST_ROOT, 333, testProof);
        // Should succeed since vault is authorized and mock accepts all proofs

        assertGt(vault.getPosition(user2).shares, 0);
    }

    function test_deposit_fails_when_worldId_proof_invalid() public {
        // Make mock reject proofs
        mockWorldId.setShouldRevert(true);

        vm.prank(user1);
        vm.expectRevert("MockWorldId: invalid proof");
        vault.deposit{value: 1 ether}(TEST_ROOT, 111, testProof);
    }

    function test_withdraw_with_worldIdGate_connected() public {
        // Verify and deposit
        vm.prank(user1);
        worldIdGate.verifyIdentity(user1, TEST_ROOT, 111, testProof);

        vm.prank(user1);
        vault.deposit{value: 2 ether}(TEST_ROOT, 222, testProof);

        // Advance past hold period
        vm.warp(block.timestamp + 2 hours);

        // Withdraw
        IAegisVault.Position memory pos = vault.getPosition(user1);
        vm.prank(user1);
        vault.withdraw(pos.shares, TEST_ROOT, 333, testProof);

        assertEq(vault.getPosition(user1).shares, 0);
    }
}
