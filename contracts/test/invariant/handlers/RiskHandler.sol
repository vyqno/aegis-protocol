// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {RiskRegistry} from "../../../src/core/RiskRegistry.sol";

/// @title RiskHandler - Bounded action handler for RiskRegistry invariant testing
/// @dev Exposes bounded risk score updates and circuit breaker actions
contract RiskHandler is Test {
    RiskRegistry public registry;
    address public sentinel;
    address public protocol;

    // Ghost variables
    uint256 public ghost_cbActivations;
    uint256 public ghost_cbDeactivations;
    uint256 public ghost_riskUpdates;

    constructor(RiskRegistry _registry, address _sentinel, address _protocol) {
        registry = _registry;
        sentinel = _sentinel;
        protocol = _protocol;
    }

    /// @notice Bounded risk score update
    function updateRisk(uint256 score) external {
        score = bound(score, 0, 10_000);

        vm.prank(sentinel);
        registry.updateRiskScore(protocol, score, bytes32(ghost_riskUpdates));
        ghost_riskUpdates++;
    }

    /// @notice Attempt circuit breaker activation (may be rate limited)
    function activateCircuitBreaker(uint256 seed) external {
        vm.prank(sentinel);
        try registry.activateCircuitBreaker(bytes32(seed)) {
            ghost_cbActivations++;
        } catch {
            // Rate limited or already active - expected
        }
    }

    /// @notice Deactivate circuit breaker (owner only)
    function deactivateCircuitBreaker() external {
        try registry.deactivateCircuitBreaker() {
            ghost_cbDeactivations++;
        } catch {
            // Not active - expected
        }
    }
}
