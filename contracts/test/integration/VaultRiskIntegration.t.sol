// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AegisVault} from "../../src/core/AegisVault.sol";
import {RiskRegistry} from "../../src/core/RiskRegistry.sol";
import {IAegisVault} from "../../src/interfaces/IAegisVault.sol";
import {IRiskRegistry} from "../../src/interfaces/IRiskRegistry.sol";
import {MockForwarder} from "../helpers/MockForwarder.sol";

/// @title VaultRiskIntegrationTest - Integration tests for AegisVault <-> RiskRegistry
/// @dev Tests circuit breaker flow, risk report propagation, and rate limiting
contract VaultRiskIntegrationTest is Test {
    AegisVault public vault;
    RiskRegistry public registry;
    MockForwarder public forwarder;

    address public user1;
    address public sentinel;

    bytes32 constant RISK_WORKFLOW_ID = bytes32(uint256(2));
    bytes10 constant TEST_WORKFLOW_NAME = bytes10("risk_sent");
    address constant TEST_WORKFLOW_OWNER = address(0xCAFE);
    uint256[8] emptyProof;

    function setUp() public {
        user1 = makeAddr("user1");
        sentinel = makeAddr("sentinel");

        forwarder = new MockForwarder();
        vault = new AegisVault(address(forwarder));
        registry = new RiskRegistry();

        // Wire contracts together
        vault.setRiskRegistry(address(registry));
        vault.setWorkflowPrefix(bytes32(uint256(1)), bytes1(0x01));
        vault.setWorkflowPrefix(RISK_WORKFLOW_ID, bytes1(0x02));
        vault.completeInitialSetup();

        registry.registerVault(address(vault));
        registry.setSentinelAuthorization(sentinel, true);
        registry.addProtocol(makeAddr("aave"), "Aave");

        vm.deal(user1, 100 ether);
    }

    // ================================================================
    //               CIRCUIT BREAKER FLOW TESTS
    // ================================================================

    function test_riskReport_activates_circuit_breaker_blocks_deposits() public {
        // Send risk report that activates circuit breaker
        bytes memory report = abi.encodePacked(
            bytes1(0x02),
            abi.encode(true, uint256(9000))
        );

        forwarder.deliverReport(
            address(vault),
            RISK_WORKFLOW_ID,
            TEST_WORKFLOW_NAME,
            TEST_WORKFLOW_OWNER,
            report
        );

        assertTrue(vault.isCircuitBreakerActive(), "CB should be active");

        // Deposit should be blocked
        vm.prank(user1);
        vm.expectRevert(IAegisVault.CircuitBreakerActive.selector);
        vault.deposit{value: 1 ether}(0, 0, emptyProof);
    }

    function test_riskReport_activates_circuit_breaker_blocks_withdrawals() public {
        // User deposits first
        vm.prank(user1);
        vault.deposit{value: 1 ether}(0, 0, emptyProof);

        // Activate circuit breaker
        bytes memory report = abi.encodePacked(
            bytes1(0x02),
            abi.encode(true, uint256(9000))
        );
        forwarder.deliverReport(
            address(vault),
            RISK_WORKFLOW_ID,
            TEST_WORKFLOW_NAME,
            TEST_WORKFLOW_OWNER,
            report
        );

        vm.warp(block.timestamp + 2 hours);

        IAegisVault.Position memory pos = vault.getPosition(user1);
        vm.prank(user1);
        vm.expectRevert(IAegisVault.CircuitBreakerActive.selector);
        vault.withdraw(pos.shares, 0, 0, emptyProof);
    }

    function test_circuit_breaker_auto_deactivates_then_deposit_works() public {
        // Activate CB
        bytes memory report = abi.encodePacked(
            bytes1(0x02),
            abi.encode(true, uint256(9000))
        );
        forwarder.deliverReport(
            address(vault),
            RISK_WORKFLOW_ID,
            TEST_WORKFLOW_NAME,
            TEST_WORKFLOW_OWNER,
            report
        );

        assertTrue(vault.isCircuitBreakerActive());

        // Advance past auto-deactivation (72 hours)
        vm.warp(block.timestamp + 73 hours);
        assertFalse(vault.isCircuitBreakerActive(), "CB should auto-deactivate");

        // Deposit should work
        vm.prank(user1);
        vault.deposit{value: 1 ether}(0, 0, emptyProof);
    }

    function test_owner_deactivates_circuit_breaker_then_withdraw_works() public {
        // Deposit, then activate CB
        vm.prank(user1);
        vault.deposit{value: 1 ether}(0, 0, emptyProof);

        bytes memory report = abi.encodePacked(
            bytes1(0x02),
            abi.encode(true, uint256(9000))
        );
        forwarder.deliverReport(
            address(vault),
            RISK_WORKFLOW_ID,
            TEST_WORKFLOW_NAME,
            TEST_WORKFLOW_OWNER,
            report
        );

        // Owner deactivates
        vault.deactivateCircuitBreaker();
        assertFalse(vault.isCircuitBreakerActive());

        // Withdraw should work
        vm.warp(block.timestamp + 2 hours);
        IAegisVault.Position memory pos = vault.getPosition(user1);
        vm.prank(user1);
        vault.withdraw(pos.shares, 0, 0, emptyProof);
    }

    // ================================================================
    //           REGISTRY CIRCUIT BREAKER RATE LIMIT
    // ================================================================

    function test_registry_circuit_breaker_rate_limit_3_per_hour() public {
        // Activate 3 times (all should succeed)
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(sentinel);
            registry.activateCircuitBreaker(bytes32(i));
            registry.deactivateCircuitBreaker();
        }

        // 4th should fail (rate limited)
        vm.prank(sentinel);
        vm.expectRevert();
        registry.activateCircuitBreaker(bytes32(uint256(3)));
    }

    function test_registry_rate_limit_resets_after_window() public {
        // Use up all activations
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(sentinel);
            registry.activateCircuitBreaker(bytes32(i));
            registry.deactivateCircuitBreaker();
        }

        // Advance past rate limit window (1 hour)
        vm.warp(block.timestamp + 1 hours + 1);

        // Should work again
        vm.prank(sentinel);
        registry.activateCircuitBreaker(bytes32(uint256(4)));
    }

    // ================================================================
    //              RISK SCORE THRESHOLD TESTS
    // ================================================================

    function test_risk_score_above_threshold_creates_alert() public {
        address protocol = makeAddr("aave");

        vm.prank(sentinel);
        registry.updateRiskScore(protocol, 8000, bytes32(uint256(1)));

        assertEq(registry.getAlertCount(protocol), 1, "Should create alert above threshold");
        assertEq(registry.totalAlerts(), 1);
    }

    function test_risk_score_below_threshold_no_alert() public {
        address protocol = makeAddr("aave");

        vm.prank(sentinel);
        registry.updateRiskScore(protocol, 5000, bytes32(uint256(1)));

        assertEq(registry.getAlertCount(protocol), 0, "Should not create alert below threshold");
    }
}
