// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {RiskRegistry} from "../../src/core/RiskRegistry.sol";
import {IRiskRegistry} from "../../src/interfaces/IRiskRegistry.sol";

/// @title RiskRegistryTest - Unit tests for RiskRegistry
contract RiskRegistryTest is Test {
    RiskRegistry public registry;

    address public owner;
    address public sentinel;
    address public vaultAddr;
    address public protocol1;
    address public protocol2;
    address public unauthorized;

    function setUp() public {
        owner = address(this);
        sentinel = makeAddr("sentinel");
        vaultAddr = makeAddr("vault");
        protocol1 = makeAddr("protocol1");
        protocol2 = makeAddr("protocol2");
        unauthorized = makeAddr("unauthorized");

        registry = new RiskRegistry();

        // Setup authorization
        registry.setSentinelAuthorization(sentinel, true);
        registry.registerVault(vaultAddr);

        // Add monitored protocols
        registry.addProtocol(protocol1, "Aave V3");
        registry.addProtocol(protocol2, "Morpho Blue");
    }

    // ================================================================
    //                    RISK EVALUATION TESTS
    // ================================================================

    function test_evaluateRisk_returns_correct_score() public view {
        uint256[] memory factors = new uint256[](3);
        factors[0] = 5000; // 50%
        factors[1] = 3000; // 30%
        factors[2] = 7000; // 70%

        uint256[] memory weights = new uint256[](3);
        weights[0] = 1;
        weights[1] = 1;
        weights[2] = 1;

        (uint256 score, bool shouldTrigger) = registry.evaluateRisk(factors, weights);
        assertEq(score, 5000, "Weighted average should be 5000");
        assertFalse(shouldTrigger, "5000 < 7000 threshold, should not trigger");
    }

    function test_evaluateRisk_triggers_above_threshold() public view {
        uint256[] memory factors = new uint256[](2);
        factors[0] = 8000;
        factors[1] = 9000;

        uint256[] memory weights = new uint256[](2);
        weights[0] = 1;
        weights[1] = 1;

        (uint256 score, bool shouldTrigger) = registry.evaluateRisk(factors, weights);
        assertEq(score, 8500, "Weighted average should be 8500");
        assertTrue(shouldTrigger, "8500 >= 7000 threshold, should trigger");
    }

    function test_evaluateRisk_score_always_in_bounds() public view {
        // Edge case: all max scores
        uint256[] memory factors = new uint256[](2);
        factors[0] = 10000;
        factors[1] = 10000;

        uint256[] memory weights = new uint256[](2);
        weights[0] = 100;
        weights[1] = 100;

        (uint256 score,) = registry.evaluateRisk(factors, weights);
        assertLe(score, 10000, "Score should never exceed MAX_RISK_SCORE");

        // Edge case: all zero scores
        factors[0] = 0;
        factors[1] = 0;
        (score,) = registry.evaluateRisk(factors, weights);
        assertEq(score, 0, "Score should be 0 for all-zero factors");
    }

    function test_evaluateRisk_does_not_modify_state() public {
        uint256[] memory factors = new uint256[](1);
        factors[0] = 8000;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1;

        // Snapshot state
        IRiskRegistry.RiskAssessment memory before = registry.getRiskAssessment(protocol1);

        // Call evaluateRisk (view function)
        registry.evaluateRisk(factors, weights);

        // State unchanged
        IRiskRegistry.RiskAssessment memory after_ = registry.getRiskAssessment(protocol1);
        assertEq(before.score, after_.score, "Score should not change from evaluateRisk");
    }

    // ================================================================
    //                    RISK SCORE UPDATE TESTS
    // ================================================================

    function test_updateRiskScore_from_sentinel() public {
        vm.prank(sentinel);
        registry.updateRiskScore(protocol1, 5000, bytes32(uint256(1)));

        IRiskRegistry.RiskAssessment memory assessment = registry.getRiskAssessment(protocol1);
        assertEq(assessment.score, 5000, "Score should be updated");
        assertEq(assessment.lastUpdated, block.timestamp, "Timestamp should be updated");
    }

    function test_updateRiskScore_from_vault() public {
        vm.prank(vaultAddr);
        registry.updateRiskScore(protocol1, 3000, bytes32(uint256(2)));

        IRiskRegistry.RiskAssessment memory assessment = registry.getRiskAssessment(protocol1);
        assertEq(assessment.score, 3000);
    }

    function test_updateRiskScore_reverts_from_unauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(IRiskRegistry.CallerNotAuthorized.selector, unauthorized)
        );
        registry.updateRiskScore(protocol1, 5000, bytes32(uint256(1)));
    }

    function test_updateRiskScore_reverts_unmonitored_protocol() public {
        address unknown = makeAddr("unknown");
        vm.prank(sentinel);
        vm.expectRevert(
            abi.encodeWithSelector(IRiskRegistry.ProtocolNotMonitored.selector, unknown)
        );
        registry.updateRiskScore(unknown, 5000, bytes32(uint256(1)));
    }

    function test_updateRiskScore_reverts_invalid_score() public {
        vm.prank(sentinel);
        vm.expectRevert(
            abi.encodeWithSelector(IRiskRegistry.InvalidRiskScore.selector, 10001)
        );
        registry.updateRiskScore(protocol1, 10001, bytes32(uint256(1)));
    }

    function test_getRiskScore_returns_stored_value() public {
        vm.prank(sentinel);
        registry.updateRiskScore(protocol1, 4200, bytes32(uint256(1)));

        IRiskRegistry.RiskAssessment memory assessment = registry.getRiskAssessment(protocol1);
        assertEq(assessment.score, 4200);
        assertTrue(assessment.isMonitored);
    }

    function test_isProtocolSafe_below_threshold() public {
        vm.prank(sentinel);
        registry.updateRiskScore(protocol1, 5000, bytes32(uint256(1)));
        assertTrue(registry.isProtocolSafe(protocol1), "Score 5000 < threshold 7000 = safe");
    }

    function test_isProtocolSafe_above_threshold() public {
        vm.prank(sentinel);
        registry.updateRiskScore(protocol1, 8000, bytes32(uint256(1)));
        assertFalse(registry.isProtocolSafe(protocol1), "Score 8000 >= threshold 7000 = unsafe");
    }

    // ================================================================
    //                    CIRCUIT BREAKER TESTS
    // ================================================================

    function test_activateCircuitBreaker_from_authorized_sentinel() public {
        vm.prank(sentinel);
        registry.activateCircuitBreaker(bytes32(uint256(1)));

        assertTrue(registry.isCircuitBreakerActive(), "CB should be active");
    }

    function test_activateCircuitBreaker_reverts_from_unauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(IRiskRegistry.CallerNotAuthorized.selector, unauthorized)
        );
        registry.activateCircuitBreaker(bytes32(uint256(1)));
    }

    function test_activateCircuitBreaker_reverts_when_already_active() public {
        vm.prank(sentinel);
        registry.activateCircuitBreaker(bytes32(uint256(1)));

        vm.prank(sentinel);
        vm.expectRevert(IRiskRegistry.CircuitBreakerAlreadyActive.selector);
        registry.activateCircuitBreaker(bytes32(uint256(2)));
    }

    function test_activateCircuitBreaker_rate_limited() public {
        // Activate and deactivate 3 times to hit the rate limit
        for (uint256 i = 1; i <= 3; i++) {
            vm.prank(sentinel);
            registry.activateCircuitBreaker(bytes32(i));

            registry.deactivateCircuitBreaker(); // owner deactivates
        }

        // 4th activation within the same hour should fail
        vm.prank(sentinel);
        vm.expectRevert(
            abi.encodeWithSelector(IRiskRegistry.CircuitBreakerRateLimited.selector, 3, 3)
        );
        registry.activateCircuitBreaker(bytes32(uint256(4)));
    }

    function test_activateCircuitBreaker_rate_resets_after_window() public {
        // Use up all 3 activations
        for (uint256 i = 1; i <= 3; i++) {
            vm.prank(sentinel);
            registry.activateCircuitBreaker(bytes32(i));
            registry.deactivateCircuitBreaker();
        }

        // Advance past rate limit window (1 hour)
        vm.warp(block.timestamp + 1 hours + 1);

        // Should succeed after window reset
        vm.prank(sentinel);
        registry.activateCircuitBreaker(bytes32(uint256(5)));
        assertTrue(registry.isCircuitBreakerActive());
    }

    function test_deactivateCircuitBreaker_by_owner() public {
        vm.prank(sentinel);
        registry.activateCircuitBreaker(bytes32(uint256(1)));

        registry.deactivateCircuitBreaker();
        assertFalse(registry.isCircuitBreakerActive());
    }

    function test_deactivateCircuitBreaker_reverts_when_not_active() public {
        vm.expectRevert(IRiskRegistry.CircuitBreakerNotActive.selector);
        registry.deactivateCircuitBreaker();
    }

    function test_circuitBreaker_auto_deactivates() public {
        vm.prank(sentinel);
        registry.activateCircuitBreaker(bytes32(uint256(1)));
        assertTrue(registry.isCircuitBreakerActive());

        // Advance past auto-deactivation period (72 hours)
        vm.warp(block.timestamp + 72 hours + 1);

        assertFalse(registry.isCircuitBreakerActive(), "Should auto-deactivate after 72h");
    }

    function test_getCircuitBreakerState() public {
        bytes32 reportId = bytes32(uint256(42));
        vm.prank(sentinel);
        registry.activateCircuitBreaker(reportId);

        IRiskRegistry.CircuitBreakerState memory state = registry.getCircuitBreakerState();
        assertTrue(state.isActive);
        assertEq(state.activatedAt, block.timestamp);
        assertEq(state.activationCount, 1);
        assertEq(state.lastTriggerReportId, reportId);
    }

    // ================================================================
    //                    THRESHOLD TESTS
    // ================================================================

    function test_updateThresholds_by_owner() public {
        registry.setThreshold(5000);
        assertEq(registry.riskThreshold(), 5000);
    }

    function test_updateThresholds_reverts_below_minimum() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IRiskRegistry.ThresholdOutOfBounds.selector,
                500,
                registry.MIN_THRESHOLD(),
                registry.MAX_THRESHOLD()
            )
        );
        registry.setThreshold(500); // Below MIN_THRESHOLD (1000)
    }

    function test_updateThresholds_reverts_above_maximum() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IRiskRegistry.ThresholdOutOfBounds.selector,
                9600,
                registry.MIN_THRESHOLD(),
                registry.MAX_THRESHOLD()
            )
        );
        registry.setThreshold(9600); // Above MAX_THRESHOLD (9500)
    }

    function test_updateThresholds_reverts_from_non_owner() public {
        vm.prank(sentinel);
        vm.expectRevert();
        registry.setThreshold(5000);
    }

    // ================================================================
    //                   PROTOCOL MANAGEMENT TESTS
    // ================================================================

    function test_registerVault_by_owner() public {
        address newVault = makeAddr("newVault");
        registry.registerVault(newVault);
        assertTrue(registry.isAuthorizedVault(newVault));
    }

    function test_removeVault_by_owner() public {
        registry.removeVault(vaultAddr);
        assertFalse(registry.isAuthorizedVault(vaultAddr));
    }

    function test_addProtocol_by_owner() public {
        address newProto = makeAddr("newProto");
        registry.addProtocol(newProto, "Compound V3");

        IRiskRegistry.RiskAssessment memory assessment = registry.getRiskAssessment(newProto);
        assertTrue(assessment.isMonitored);
        assertEq(assessment.score, 0);
    }

    function test_addProtocol_reverts_zero_address() public {
        vm.expectRevert(IRiskRegistry.ZeroAddress.selector);
        registry.addProtocol(address(0), "Invalid");
    }

    function test_removeProtocol_by_owner() public {
        registry.removeProtocol(protocol1);

        IRiskRegistry.RiskAssessment memory assessment = registry.getRiskAssessment(protocol1);
        assertFalse(assessment.isMonitored);
    }

    function test_removeProtocol_reverts_unmonitored() public {
        address unknown = makeAddr("unknown");
        vm.expectRevert(
            abi.encodeWithSelector(IRiskRegistry.ProtocolNotMonitored.selector, unknown)
        );
        registry.removeProtocol(unknown);
    }

    // ================================================================
    //                    ALERT COUNTER TESTS
    // ================================================================

    function test_alertCount_increments_correctly() public {
        // Set score above threshold to trigger alert
        vm.prank(sentinel);
        registry.updateRiskScore(protocol1, 8000, bytes32(uint256(1)));
        assertEq(registry.getAlertCount(protocol1), 1, "Alert count should be 1");

        // Another high score
        vm.prank(sentinel);
        registry.updateRiskScore(protocol1, 9000, bytes32(uint256(2)));
        assertEq(registry.getAlertCount(protocol1), 2, "Alert count should be 2");

        // Score below threshold - no alert
        vm.prank(sentinel);
        registry.updateRiskScore(protocol1, 3000, bytes32(uint256(3)));
        assertEq(registry.getAlertCount(protocol1), 2, "Alert count should still be 2");

        assertEq(registry.totalAlerts(), 2, "Total alerts should be 2");
    }

    function test_healthFactor_below_minimum_triggers_alert() public {
        // High risk score (above threshold) creates an alert
        vm.prank(sentinel);
        registry.updateRiskScore(protocol1, 9500, bytes32(uint256(1)));

        assertFalse(registry.isProtocolSafe(protocol1));
        assertEq(registry.getAlertCount(protocol1), 1);
    }

    // ================================================================
    //                    PAUSABLE TESTS
    // ================================================================

    function test_pause_blocks_risk_updates() public {
        registry.pause();

        vm.prank(sentinel);
        vm.expectRevert();
        registry.updateRiskScore(protocol1, 5000, bytes32(uint256(1)));
    }

    function test_pause_blocks_circuit_breaker() public {
        registry.pause();

        vm.prank(sentinel);
        vm.expectRevert();
        registry.activateCircuitBreaker(bytes32(uint256(1)));
    }

    function test_unpause_restores_functionality() public {
        registry.pause();
        registry.unpause();

        vm.prank(sentinel);
        registry.updateRiskScore(protocol1, 5000, bytes32(uint256(1)));
        assertEq(registry.getRiskAssessment(protocol1).score, 5000);
    }

    // ================================================================
    //                   OWNABLE2STEP TESTS
    // ================================================================

    function test_ownership_is_two_step() public {
        address newOwner = makeAddr("newOwner");

        registry.transferOwnership(newOwner);
        assertEq(registry.owner(), address(this), "Owner should not change yet");
        assertEq(registry.pendingOwner(), newOwner);

        vm.prank(newOwner);
        registry.acceptOwnership();
        assertEq(registry.owner(), newOwner);
    }

    // ================================================================
    //                   CONFIGURATION TESTS
    // ================================================================

    function test_setMaxActivationsPerWindow() public {
        registry.setMaxActivationsPerWindow(5);
        assertEq(registry.maxActivationsPerWindow(), 5);
    }

    function test_setAutoDeactivationPeriod() public {
        registry.setAutoDeactivationPeriod(48 hours);
        assertEq(registry.autoDeactivationPeriod(), 48 hours);
    }

    function test_setAutoDeactivationPeriod_reverts_below_minimum() public {
        vm.expectRevert();
        registry.setAutoDeactivationPeriod(30 minutes); // Below 1 hour minimum
    }
}
