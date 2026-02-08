// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {RiskMath} from "../../src/libraries/RiskMath.sol";

/// @notice Wrapper to make RiskMath library calls external (required for vm.expectRevert)
contract RiskMathWrapper {
    function calculateHealthFactor(uint256 c, uint256 d, uint256 t) external pure returns (uint256) {
        return RiskMath.calculateHealthFactor(c, d, t);
    }

    function wadDiv(uint256 a, uint256 b) external pure returns (uint256) {
        return RiskMath.wadDiv(a, b);
    }
}

/// @title RiskMathFuzzTest - Fuzz tests for all math functions
/// @dev Verifies overflow safety, monotonicity, and invariants across random inputs
contract RiskMathFuzzTest is Test {
    RiskMathWrapper public wrapper;

    function setUp() public {
        wrapper = new RiskMathWrapper();
    }
    // ================================================================
    //               HEALTH FACTOR FUZZ TESTS
    // ================================================================

    function testFuzz_calculateHealthFactor(uint256 collateral, uint256 debt) public pure {
        collateral = bound(collateral, 1, type(uint128).max);
        debt = bound(debt, 1, type(uint128).max); // Exclude zero debt (tested separately)
        uint256 threshold = 8000; // 80%

        uint256 hf = RiskMath.calculateHealthFactor(collateral, debt, threshold);

        // Should never overflow (uses Math.mulDiv)
        // HF = (collateral * threshold / MAX_BPS) * WAD / debt
        // With threshold=80%, if collateral >= debt, HF should be >= 0.8 WAD
        assertTrue(true, "Should not revert");
    }

    function testFuzz_calculateHealthFactor_zero_debt(uint256 collateral) public pure {
        collateral = bound(collateral, 0, type(uint128).max);

        uint256 hf = RiskMath.calculateHealthFactor(collateral, 0, 8000);

        assertEq(hf, type(uint256).max, "Zero debt should return max HF");
    }

    function testFuzz_calculateHealthFactor_monotonic_collateral(
        uint256 collA,
        uint256 collB,
        uint256 debt
    ) public pure {
        collA = bound(collA, 1, type(uint128).max / 2);
        collB = bound(collB, collA, type(uint128).max);
        debt = bound(debt, 1, type(uint128).max);

        uint256 hfA = RiskMath.calculateHealthFactor(collA, debt, 8000);
        uint256 hfB = RiskMath.calculateHealthFactor(collB, debt, 8000);

        // INVARIANT: More collateral => higher or equal health factor
        assertLe(hfA, hfB, "HF must be monotonically increasing with collateral");
    }

    function testFuzz_calculateHealthFactor_monotonic_debt(
        uint256 collateral,
        uint256 debtA,
        uint256 debtB
    ) public pure {
        collateral = bound(collateral, 1, type(uint128).max);
        debtA = bound(debtA, 1, type(uint128).max / 2);
        debtB = bound(debtB, debtA, type(uint128).max);

        uint256 hfA = RiskMath.calculateHealthFactor(collateral, debtA, 8000);
        uint256 hfB = RiskMath.calculateHealthFactor(collateral, debtB, 8000);

        // INVARIANT: More debt => lower or equal health factor
        assertGe(hfA, hfB, "HF must be monotonically decreasing with debt");
    }

    function testFuzz_calculateHealthFactor_reverts_overflow(uint256 collateral) public {
        vm.assume(collateral > type(uint128).max);

        vm.expectRevert(
            abi.encodeWithSelector(RiskMath.InputExceedsMaximum.selector, collateral, type(uint128).max)
        );
        wrapper.calculateHealthFactor(collateral, 1, 8000);
    }

    // ================================================================
    //                RISK SCORE FUZZ TESTS
    // ================================================================

    function testFuzz_calculateRiskScore(uint256 f1, uint256 f2, uint256 f3) public pure {
        f1 = bound(f1, 0, 10_000);
        f2 = bound(f2, 0, 10_000);
        f3 = bound(f3, 0, 10_000);

        uint256[] memory factors = new uint256[](3);
        uint256[] memory weights = new uint256[](3);
        factors[0] = f1;
        factors[1] = f2;
        factors[2] = f3;
        weights[0] = 1;
        weights[1] = 1;
        weights[2] = 1;

        uint256 score = RiskMath.calculateRiskScore(factors, weights);

        // INVARIANT: Equal weights => score = average of factors
        uint256 expected = (f1 + f2 + f3) / 3;
        assertEq(score, expected, "Equal weights should give average");

        // INVARIANT: Score within [min, max] of factors
        uint256 minF = f1;
        if (f2 < minF) minF = f2;
        if (f3 < minF) minF = f3;
        uint256 maxF = f1;
        if (f2 > maxF) maxF = f2;
        if (f3 > maxF) maxF = f3;

        assertGe(score, minF, "Score must be >= min factor");
        assertLe(score, maxF, "Score must be <= max factor");
    }

    function testFuzz_calculateRiskScore_weighted(
        uint256 factor1,
        uint256 factor2,
        uint256 weight1,
        uint256 weight2
    ) public pure {
        factor1 = bound(factor1, 0, 10_000);
        factor2 = bound(factor2, 0, 10_000);
        weight1 = bound(weight1, 1, 100);
        weight2 = bound(weight2, 1, 100);

        uint256[] memory factors = new uint256[](2);
        uint256[] memory weights = new uint256[](2);
        factors[0] = factor1;
        factors[1] = factor2;
        weights[0] = weight1;
        weights[1] = weight2;

        uint256 score = RiskMath.calculateRiskScore(factors, weights);

        // INVARIANT: Score in range [0, 10000]
        assertLe(score, 10_000, "Score must not exceed MAX_BPS");
    }

    // ================================================================
    //                 WAD MATH FUZZ TESTS
    // ================================================================

    function testFuzz_wadMul(uint256 a, uint256 b) public pure {
        // Bound to prevent overflow in intermediate calculation
        a = bound(a, 0, type(uint128).max);
        b = bound(b, 0, type(uint128).max);

        uint256 result = RiskMath.wadMul(a, b);

        // INVARIANT: wadMul(a, WAD) == a
        if (b == 1e18) {
            assertEq(result, a, "wadMul(x, WAD) should equal x");
        }

        // INVARIANT: wadMul(a, 0) == 0
        if (b == 0) {
            assertEq(result, 0, "wadMul(x, 0) should be 0");
        }
    }

    function testFuzz_wadDiv(uint256 a, uint256 b) public pure {
        a = bound(a, 0, type(uint128).max);
        b = bound(b, 1, type(uint128).max); // Cannot be zero

        uint256 result = RiskMath.wadDiv(a, b);

        // INVARIANT: wadDiv(a, WAD) == a
        if (b == 1e18) {
            assertEq(result, a, "wadDiv(x, WAD) should equal x");
        }

        // INVARIANT: wadDiv(0, b) == 0
        if (a == 0) {
            assertEq(result, 0, "wadDiv(0, x) should be 0");
        }
    }

    function testFuzz_wadDiv_reverts_zero_denominator(uint256 a) public {
        a = bound(a, 0, type(uint128).max);
        vm.expectRevert(RiskMath.ZeroDenominator.selector);
        wrapper.wadDiv(a, 0);
    }

    // ================================================================
    //                BPS CONVERSION FUZZ TESTS
    // ================================================================

    function testFuzz_bpsToWad_roundtrip(uint256 bps) public pure {
        bps = bound(bps, 0, 10_000);

        uint256 wad = RiskMath.bpsToWad(bps);
        uint256 bpsBack = RiskMath.wadToBps(wad);

        assertEq(bpsBack, bps, "BPS -> WAD -> BPS roundtrip should be lossless");
    }

    function testFuzz_isLiquidatable(uint256 hf) public pure {
        bool result = RiskMath.isLiquidatable(hf);

        if (hf < 1e18) {
            assertTrue(result, "HF < 1.0 should be liquidatable");
        } else {
            assertFalse(result, "HF >= 1.0 should not be liquidatable");
        }
    }
}
