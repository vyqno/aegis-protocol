// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title RiskMath - Risk score calculations and health factor math for AEGIS Protocol
/// @notice All math uses 1e18 precision (WAD math) with OpenZeppelin Math.mulDiv
///         to prevent intermediate overflow. NO unchecked blocks are used (see VULN-003).
/// @dev Bounds: collateral and debt values MUST be <= type(uint128).max to prevent
///      overflow in intermediate calculations even with safe math.
library RiskMath {
    /// @notice 1e18 precision constant for WAD math
    uint256 internal constant WAD = 1e18;

    /// @notice Maximum basis points (100.00%)
    uint256 internal constant MAX_BPS = 10_000;

    /// @notice Health factor threshold below which a position is liquidatable
    uint256 internal constant LIQUIDATION_THRESHOLD = 1e18; // 1.0 in WAD

    /// @notice Maximum allowed input value to prevent overflow in intermediate math
    uint256 internal constant MAX_INPUT = type(uint128).max;

    error InputExceedsMaximum(uint256 value, uint256 maximum);
    error ZeroDenominator();
    error ArrayLengthMismatch(uint256 factorsLength, uint256 weightsLength);
    error EmptyArray();
    error WeightsSumZero();

    /// @notice Calculate the health factor of a position
    /// @param collateral The collateral value in wei
    /// @param debt The debt value in wei
    /// @param threshold The liquidation threshold in basis points (0-10000)
    /// @return healthFactor The health factor in WAD (1e18 = 1.0)
    /// @dev healthFactor = (collateral * threshold / MAX_BPS) / debt, scaled to WAD
    ///      Returns type(uint256).max if debt is 0 (no risk)
    function calculateHealthFactor(
        uint256 collateral,
        uint256 debt,
        uint256 threshold
    ) internal pure returns (uint256 healthFactor) {
        if (debt == 0) {
            return type(uint256).max;
        }
        if (collateral > MAX_INPUT) {
            revert InputExceedsMaximum(collateral, MAX_INPUT);
        }
        if (threshold > MAX_BPS) {
            revert InputExceedsMaximum(threshold, MAX_BPS);
        }

        // adjustedCollateral = collateral * threshold / MAX_BPS
        uint256 adjustedCollateral = Math.mulDiv(collateral, threshold, MAX_BPS);

        // healthFactor = adjustedCollateral * WAD / debt
        healthFactor = Math.mulDiv(adjustedCollateral, WAD, debt);
    }

    /// @notice Calculate a weighted risk score from multiple factors
    /// @param factors Array of risk factor scores (each 0-10000 in basis points)
    /// @param weights Array of weights for each factor (arbitrary scale, will be normalized)
    /// @return score The weighted average risk score in basis points (0-10000)
    /// @dev score = sum(factors[i] * weights[i]) / sum(weights)
    function calculateRiskScore(
        uint256[] memory factors,
        uint256[] memory weights
    ) internal pure returns (uint256 score) {
        if (factors.length != weights.length) {
            revert ArrayLengthMismatch(factors.length, weights.length);
        }
        if (factors.length == 0) {
            revert EmptyArray();
        }

        uint256 weightedSum;
        uint256 totalWeight;

        for (uint256 i; i < factors.length; ++i) {
            if (factors[i] > MAX_BPS) {
                revert InputExceedsMaximum(factors[i], MAX_BPS);
            }
            weightedSum += factors[i] * weights[i];
            totalWeight += weights[i];
        }

        if (totalWeight == 0) {
            revert WeightsSumZero();
        }

        score = weightedSum / totalWeight;
    }

    /// @notice Check if a position is liquidatable based on its health factor
    /// @param healthFactor The health factor in WAD
    /// @return True if the health factor is below the liquidation threshold
    function isLiquidatable(uint256 healthFactor) internal pure returns (bool) {
        return healthFactor < LIQUIDATION_THRESHOLD;
    }

    /// @notice Safe WAD multiplication: (a * b) / WAD
    /// @param a First operand
    /// @param b Second operand
    /// @return result The result of (a * b) / WAD
    function wadMul(uint256 a, uint256 b) internal pure returns (uint256 result) {
        result = Math.mulDiv(a, b, WAD);
    }

    /// @notice Safe WAD division: (a * WAD) / b
    /// @param a Numerator
    /// @param b Denominator
    /// @return result The result of (a * WAD) / b
    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256 result) {
        if (b == 0) {
            revert ZeroDenominator();
        }
        result = Math.mulDiv(a, WAD, b);
    }

    /// @notice Convert basis points to WAD
    /// @param bps Value in basis points (0-10000)
    /// @return WAD representation
    function bpsToWad(uint256 bps) internal pure returns (uint256) {
        return Math.mulDiv(bps, WAD, MAX_BPS);
    }

    /// @notice Convert WAD to basis points
    /// @param wadValue Value in WAD
    /// @return Basis points representation (0-10000)
    function wadToBps(uint256 wadValue) internal pure returns (uint256) {
        return Math.mulDiv(wadValue, MAX_BPS, WAD);
    }
}
