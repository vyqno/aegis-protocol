// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {RiskRegistry} from "../../src/core/RiskRegistry.sol";
import {IRiskRegistry} from "../../src/interfaces/IRiskRegistry.sol";

/// @title RiskRegistryFuzzTest - Fuzz tests for risk scores and circuit breaker
contract RiskRegistryFuzzTest is Test {
    RiskRegistry public registry;

    address public sentinel;
    address public protocol;

    function setUp() public {
        registry = new RiskRegistry();
        sentinel = makeAddr("sentinel");
        protocol = makeAddr("protocol");

        registry.addProtocol(protocol, "TestProtocol");
        registry.setSentinelAuthorization(sentinel, true);
    }

    // ================================================================
    //                   RISK SCORE FUZZ TESTS
    // ================================================================

    function testFuzz_updateRiskScore_within_bounds(uint256 score) public {
        score = bound(score, 0, 10_000);

        vm.prank(sentinel);
        registry.updateRiskScore(protocol, score, bytes32(uint256(1)));

        IRiskRegistry.RiskAssessment memory assessment = registry.getRiskAssessment(protocol);
        assertEq(assessment.score, score, "Score should match");
        assertTrue(assessment.isMonitored);
    }

    function testFuzz_updateRiskScore_reverts_above_max(uint256 score) public {
        score = bound(score, 10_001, type(uint256).max);

        vm.prank(sentinel);
        vm.expectRevert(abi.encodeWithSelector(IRiskRegistry.InvalidRiskScore.selector, score));
        registry.updateRiskScore(protocol, score, bytes32(uint256(1)));
    }

    function testFuzz_evaluateRisk_weighted(
        uint256 factor1,
        uint256 factor2,
        uint256 weight1,
        uint256 weight2
    ) public view {
        factor1 = bound(factor1, 0, 10_000);
        factor2 = bound(factor2, 0, 10_000);
        weight1 = bound(weight1, 1, 1000);
        weight2 = bound(weight2, 1, 1000);

        uint256[] memory factors = new uint256[](2);
        uint256[] memory weights = new uint256[](2);
        factors[0] = factor1;
        factors[1] = factor2;
        weights[0] = weight1;
        weights[1] = weight2;

        (uint256 score,) = registry.evaluateRisk(factors, weights);

        // INVARIANT: Score must be within [0, 10000]
        assertLe(score, 10_000, "Score must not exceed MAX");

        // INVARIANT: Score must be between min and max of factors
        uint256 minFactor = factor1 < factor2 ? factor1 : factor2;
        uint256 maxFactor = factor1 > factor2 ? factor1 : factor2;
        assertGe(score, minFactor, "Score must be >= min factor");
        assertLe(score, maxFactor, "Score must be <= max factor");
    }

    // ================================================================
    //                 THRESHOLD FUZZ TESTS
    // ================================================================

    function testFuzz_setThreshold_valid(uint256 threshold) public {
        threshold = bound(threshold, 1_000, 9_500);

        registry.setThreshold(threshold);
        assertEq(registry.riskThreshold(), threshold);
    }

    function testFuzz_setThreshold_reverts_below_min(uint256 threshold) public {
        threshold = bound(threshold, 0, 999);

        vm.expectRevert(
            abi.encodeWithSelector(IRiskRegistry.ThresholdOutOfBounds.selector, threshold, 1_000, 9_500)
        );
        registry.setThreshold(threshold);
    }

    function testFuzz_setThreshold_reverts_above_max(uint256 threshold) public {
        threshold = bound(threshold, 9_501, type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(IRiskRegistry.ThresholdOutOfBounds.selector, threshold, 1_000, 9_500)
        );
        registry.setThreshold(threshold);
    }

    // ================================================================
    //             CIRCUIT BREAKER RATE LIMIT FUZZ
    // ================================================================

    function testFuzz_circuitBreaker_rate_limited(uint256 activations) public {
        activations = bound(activations, 1, 10);

        for (uint256 i = 0; i < activations; i++) {
            if (i >= 3) {
                // Should be rate limited after 3 activations
                vm.prank(sentinel);
                vm.expectRevert();
                registry.activateCircuitBreaker(bytes32(i));
                break;
            }

            vm.prank(sentinel);
            registry.activateCircuitBreaker(bytes32(i));

            // Deactivate to allow next activation
            registry.deactivateCircuitBreaker();
        }
    }

    // ================================================================
    //                 ALERT COUNTER FUZZ TESTS
    // ================================================================

    function testFuzz_alertCounter_increments(uint256 numUpdates) public {
        numUpdates = bound(numUpdates, 1, 20);

        uint256 expectedAlerts;
        uint256 threshold = registry.riskThreshold();

        for (uint256 i = 0; i < numUpdates; i++) {
            uint256 score = (i % 2 == 0) ? threshold + 100 : threshold - 100;
            if (score > 10_000) score = 10_000;

            vm.prank(sentinel);
            registry.updateRiskScore(protocol, score, bytes32(i));

            if (score >= threshold) {
                expectedAlerts++;
            }
        }

        assertEq(registry.getAlertCount(protocol), expectedAlerts, "Alert count mismatch");
    }
}
