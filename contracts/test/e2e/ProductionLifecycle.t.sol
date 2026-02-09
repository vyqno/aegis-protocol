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
import {TestConstants} from "../helpers/TestConstants.sol";

/// @title ProductionLifecycle - Real-time production simulation test suite
/// @notice Tests the AEGIS protocol as it would operate in production over extended periods.
///         Covers multi-user scenarios, multi-day operations, edge cases, and failure recovery.
///         This is the "does it actually work?" test — if this passes, the system is production-ready.
contract ProductionLifecycleTest is Test {
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

    address public admin;
    address[] public users;
    address public aavePool;
    address public compoundPool;

    bytes32 constant YIELD_WORKFLOW_ID = bytes32(uint256(1));
    bytes32 constant RISK_WORKFLOW_ID = bytes32(uint256(2));
    bytes32 constant VAULT_WORKFLOW_ID = bytes32(uint256(3));
    bytes10 constant WF_NAME = bytes10("cre_aegis");
    address constant WF_OWNER = address(0xCAFE);

    uint256[8] emptyProof;
    uint256 reportNonce;

    function setUp() public {
        admin = address(this);
        aavePool = address(0xBE5E5728dB7F0E23E20B87E3737445796b272484);
        compoundPool = makeAddr("compound");

        // Create 10 users
        for (uint256 i = 0; i < 10; i++) {
            address user = makeAddr(string(abi.encodePacked("user", vm.toString(i))));
            users.push(user);
            vm.deal(user, 100 ether);
        }

        // Deploy
        forwarder = new MockForwarder();
        ccipRouter = new MockCCIPRouter();
        mockWorldId = new MockWorldId();

        worldIdGate = new WorldIdGate(address(mockWorldId), 1, "aegis-vault", 24 hours);
        registry = new RiskRegistry();
        router = new StrategyRouter(address(ccipRouter));
        vault = new AegisVault(address(forwarder));

        // Wire
        vault.setRiskRegistry(address(registry));
        vault.setStrategyRouter(address(router));
        vault.setWorldIdGate(address(worldIdGate));
        worldIdGate.registerVault(address(vault));
        registry.registerVault(address(vault));
        registry.setSentinelAuthorization(admin, true);
        router.setVault(address(vault));
        router.setRiskRegistry(address(registry));
        router.setAllowedChain(TestConstants.SEPOLIA_CHAIN_SELECTOR, true);
        router.setChainReceiver(TestConstants.SEPOLIA_CHAIN_SELECTOR, address(router));

        registry.addProtocol(aavePool, "Aave V3");
        registry.addProtocol(compoundPool, "Compound V3");

        vault.setWorkflowPrefix(YIELD_WORKFLOW_ID, bytes1(0x01));
        vault.setWorkflowPrefix(RISK_WORKFLOW_ID, bytes1(0x02));
        vault.setWorkflowPrefix(VAULT_WORKFLOW_ID, bytes1(0x03));

        vault.completeInitialSetup();
    }

    // ================================================================
    //       SCENARIO 1: Normal Day - Multi-User Operations
    // ================================================================

    /// @notice 24-hour normal operations: 10 users deposit, yield ticks, some withdraw
    function test_scenario_normalDay() public {
        uint256 t0 = block.timestamp;

        // Morning: 5 users deposit
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(users[i]);
            vault.deposit{value: (i + 1) * 1 ether}(0, i + 100, emptyProof);
        }
        // Total: 1+2+3+4+5 = 15 ETH
        assertEq(vault.getTotalAssets(), 15 ether, "Total assets after morning deposits");

        // Yield scanner ticks every 5 minutes for 1 hour (12 ticks)
        for (uint256 tick = 1; tick <= 12; tick++) {
            vm.warp(t0 + tick * 5 minutes);
            _sendYieldReport(6000 + tick * 100);
        }

        // Afternoon: 5 more users deposit
        vm.warp(t0 + 2 hours);
        for (uint256 i = 5; i < 10; i++) {
            vm.prank(users[i]);
            vault.deposit{value: 2 ether}(0, i + 100, emptyProof);
        }
        // Total: 15 + 10 = 25 ETH
        assertEq(vault.getTotalAssets(), 25 ether, "Total assets after afternoon deposits");

        // Evening: first 3 users withdraw (past hold period)
        for (uint256 i = 0; i < 3; i++) {
            IAegisVault.Position memory pos = vault.getPosition(users[i]);
            vm.prank(users[i]);
            vault.withdraw(pos.shares, 0, 0, emptyProof);
            assertEq(vault.getPosition(users[i]).shares, 0, "Fully withdrawn");
        }

        // Remaining assets: 25 - 1 - 2 - 3 = 19 ETH (approx, due to virtual shares rounding)
        uint256 remaining = vault.getTotalAssets();
        assertGt(remaining, 18 ether, "Should have ~19 ETH remaining");
        assertLt(remaining, 20 ether, "Should have ~19 ETH remaining");
    }

    // ================================================================
    //       SCENARIO 2: Risk Event - Circuit Breaker Emergency
    // ================================================================

    /// @notice Risk event: users deposit, risk alert fires, CB activates, recovery
    function test_scenario_riskEvent() public {
        uint256 t0 = block.timestamp;

        // Users deposit
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(users[i]);
            vault.deposit{value: 5 ether}(0, i + 200, emptyProof);
        }
        assertEq(vault.getTotalAssets(), 25 ether);

        // Normal yield ticks
        vm.warp(t0 + 5 minutes);
        _sendYieldReport(7000);

        // Risk alert: Aave score spikes to 9000
        vm.warp(t0 + 10 minutes);
        registry.updateRiskScore(aavePool, 9000, bytes32(uint256(300)));

        // Risk sentinel activates CB
        _sendRiskReport(true, 9500);
        assertTrue(vault.isCircuitBreakerActive(), "CB should be active");

        // All user operations blocked
        vm.prank(users[0]);
        vm.expectRevert(IAegisVault.CircuitBreakerActive.selector);
        vault.deposit{value: 1 ether}(0, 0, emptyProof);

        // Admin deactivates CB after investigation
        vm.warp(t0 + 1 hours);
        vault.deactivateCircuitBreaker();
        assertFalse(vault.isCircuitBreakerActive(), "CB should be inactive after admin deactivation");

        // Operations resume
        vm.prank(users[0]);
        vault.deposit{value: 1 ether}(0, 999, emptyProof);
        assertEq(vault.getTotalAssets(), 26 ether, "Total after post-CB deposit");
    }

    // ================================================================
    //       SCENARIO 3: World ID Verification Lifecycle
    // ================================================================

    /// @notice Verify -> deposit -> TTL expires -> re-verify -> deposit again
    function test_scenario_worldIdLifecycle() public {
        // Step 1: Verify identity
        vm.prank(users[0]);
        worldIdGate.verifyIdentity(users[0], 12345, 500, emptyProof);
        assertTrue(worldIdGate.isVerified(users[0]));

        // Step 2: Deposit while verified
        vm.prank(users[0]);
        vault.deposit{value: 5 ether}(12345, 501, emptyProof);

        // Step 3: TTL expires (24 hours)
        vm.warp(block.timestamp + 25 hours);
        assertFalse(worldIdGate.isVerified(users[0]), "Verification should expire");

        // Step 4: Re-verify with new nullifier
        vm.prank(users[0]);
        worldIdGate.verifyIdentity(users[0], 12345, 502, emptyProof);
        assertTrue(worldIdGate.isVerified(users[0]), "Should be re-verified");

        // Step 5: Can deposit again
        vm.prank(users[0]);
        vault.deposit{value: 3 ether}(12345, 503, emptyProof);
        assertEq(vault.getTotalAssets(), 8 ether);
    }

    /// @notice Admin revokes verification, user re-verifies
    function test_scenario_worldIdRevocation() public {
        vm.prank(users[0]);
        worldIdGate.verifyIdentity(users[0], 12345, 600, emptyProof);

        // Admin revokes
        worldIdGate.revokeVerification(users[0]);
        assertFalse(worldIdGate.isVerified(users[0]), "Should be revoked");

        // User re-verifies with new nullifier
        vm.prank(users[0]);
        worldIdGate.verifyIdentity(users[0], 12345, 601, emptyProof);
        assertTrue(worldIdGate.isVerified(users[0]), "Should be re-verified");
    }

    // ================================================================
    //       SCENARIO 4: Cross-Chain Operations
    // ================================================================

    /// @notice Full CCIP bridge flow: deposit -> yield recommends rebalance -> bridge
    function test_scenario_crossChainBridge() public {
        vm.prank(users[0]);
        vault.deposit{value: 10 ether}(0, 0, emptyProof);

        router.updateTotalVaultValue(10 ether);

        // Yield scanner recommends rebalance to Base Sepolia
        _sendYieldReport(8500);

        // Bridge 1 ETH
        vm.deal(admin, 10 ether);
        router.bridgeAssets{value: 0.01 ether}(
            TestConstants.SEPOLIA_CHAIN_SELECTOR,
            address(router),
            1 ether
        );

        assertEq(router.getCurrentNonce(), 1, "Nonce should be 1");
        assertEq(ccipRouter.getSentMessageCount(), 1, "1 message sent");
    }

    /// @notice Strategy execution with circuit breaker check
    function test_scenario_strategyExecutionCBCheck() public {
        vm.prank(users[0]);
        vault.deposit{value: 10 ether}(0, 0, emptyProof);

        // Execute strategy normally
        IStrategyRouter.StrategyParams memory params = IStrategyRouter.StrategyParams({
            targetProtocol: aavePool,
            destinationChainSelector: TestConstants.SEPOLIA_CHAIN_SELECTOR,
            amount: 1 ether,
            strategyData: "",
            actionType: bytes1(0x01)
        });
        router.executeStrategy(params, bytes32(uint256(1)));

        // Activate CB on registry
        registry.activateCircuitBreaker(bytes32(uint256(2)));

        // Strategy execution blocked
        vm.expectRevert(IStrategyRouter.CircuitBreakerActive.selector);
        router.executeStrategy(params, bytes32(uint256(3)));
    }

    // ================================================================
    //       SCENARIO 5: Edge Cases and Failure Recovery
    // ================================================================

    /// @notice Multiple rapid deposits from same user
    function test_edge_rapidDeposits() public {
        vm.startPrank(users[0]);
        for (uint256 i = 0; i < 5; i++) {
            vault.deposit{value: 1 ether}(0, i + 700, emptyProof);
        }
        vm.stopPrank();

        assertEq(vault.getTotalAssets(), 5 ether, "All rapid deposits counted");
        assertEq(vault.getPosition(users[0]).depositAmount, 5 ether, "Deposit amount accumulated");
    }

    /// @notice Partial withdrawal
    function test_edge_partialWithdrawal() public {
        vm.prank(users[0]);
        vault.deposit{value: 10 ether}(0, 0, emptyProof);

        vm.warp(block.timestamp + 2 hours);

        IAegisVault.Position memory pos = vault.getPosition(users[0]);
        uint256 halfShares = pos.shares / 2;

        vm.prank(users[0]);
        vault.withdraw(halfShares, 0, 0, emptyProof);

        IAegisVault.Position memory posAfter = vault.getPosition(users[0]);
        assertGt(posAfter.shares, 0, "Should still have shares");
        assertApproxEqRel(posAfter.shares, halfShares, 0.01e18, "Should have ~half shares");
    }

    /// @notice Circuit breaker auto-deactivation after exactly 72 hours
    function test_edge_cbAutoDeactivationBoundary() public {
        _sendRiskReport(true, 9000);
        assertTrue(vault.isCircuitBreakerActive());

        // At exactly 72 hours: still active
        vm.warp(block.timestamp + 72 hours);
        assertTrue(vault.isCircuitBreakerActive(), "Should still be active at exactly 72h");

        // At 72h + 1s: auto-deactivated
        vm.warp(block.timestamp + 1);
        assertFalse(vault.isCircuitBreakerActive(), "Should auto-deactivate after 72h");
    }

    /// @notice Risk threshold boundary: score at exactly threshold
    function test_edge_riskScoreAtThreshold() public {
        // Default threshold is 7000
        registry.updateRiskScore(aavePool, 7000, bytes32(uint256(1)));

        // Score >= threshold should trigger alert
        uint256 alertCount = registry.getAlertCount(aavePool);
        assertEq(alertCount, 1, "Alert should be created at exact threshold");

        // Score just below threshold: no alert
        registry.updateRiskScore(aavePool, 6999, bytes32(uint256(2)));
        assertEq(registry.getAlertCount(aavePool), 1, "No new alert below threshold");
    }

    /// @notice Multiple protocol risk monitoring
    function test_edge_multiProtocolRisk() public {
        registry.updateRiskScore(aavePool, 5000, bytes32(uint256(10)));
        registry.updateRiskScore(compoundPool, 8000, bytes32(uint256(11)));

        assertTrue(registry.isProtocolSafe(aavePool), "Aave should be safe (5000 < 7000)");
        assertFalse(registry.isProtocolSafe(compoundPool), "Compound should be unsafe (8000 >= 7000)");

        assertEq(registry.getAlertCount(compoundPool), 1, "Compound should have 1 alert");
        assertEq(registry.getAlertCount(aavePool), 0, "Aave should have 0 alerts");
    }

    /// @notice Recovery after CB: verify state is clean
    function test_edge_stateAfterCBRecovery() public {
        // Deposit
        vm.prank(users[0]);
        vault.deposit{value: 5 ether}(0, 5000, emptyProof);

        // Activate and deactivate CB
        _sendRiskReport(true, 9000);
        assertTrue(vault.isCircuitBreakerActive());

        vault.deactivateCircuitBreaker();
        assertFalse(vault.isCircuitBreakerActive());

        // Verify vault state is fully functional
        vm.prank(users[1]);
        vault.deposit{value: 3 ether}(0, 5001, emptyProof);
        assertEq(vault.getTotalAssets(), 8 ether, "Vault should be fully operational after CB recovery");

        // Yield scanner should work
        _sendYieldReport(7000);

        // Withdraw should work
        vm.warp(block.timestamp + 2 hours);
        IAegisVault.Position memory pos = vault.getPosition(users[0]);
        vm.prank(users[0]);
        vault.withdraw(pos.shares, 0, 5002, emptyProof);
    }

    // ================================================================
    //       SCENARIO 6: Admin Operations
    // ================================================================

    /// @notice Full admin workflow: adjust params, add/remove protocols, ownership transfer
    function test_scenario_adminWorkflow() public {
        // Adjust vault params
        vault.setMinDeposit(0.01 ether);
        assertEq(vault.minDeposit(), 0.01 ether);

        vault.setMinHoldPeriod(30 minutes);
        assertEq(vault.minHoldPeriod(), 30 minutes);

        // Adjust registry params
        registry.setThreshold(8000);
        assertEq(registry.riskThreshold(), 8000);

        // Add new protocol
        address newProtocol = makeAddr("newProtocol");
        registry.addProtocol(newProtocol, "New Protocol");
        assertTrue(registry.getRiskAssessment(newProtocol).isMonitored);

        // Remove protocol
        registry.removeProtocol(newProtocol);
        assertFalse(registry.getRiskAssessment(newProtocol).isMonitored);

        // Ownership transfer (2-step)
        address newOwner = makeAddr("newOwner");
        vault.transferOwnership(newOwner);
        assertEq(vault.owner(), admin, "Owner should not change yet");

        vm.prank(newOwner);
        vault.acceptOwnership();
        assertEq(vault.owner(), newOwner, "Ownership transferred");
    }

    /// @notice Emergency pause and unpause
    function test_scenario_emergencyPause() public {
        vm.prank(users[0]);
        vault.deposit{value: 5 ether}(0, 6000, emptyProof);

        // Pause
        vault.pause();

        // All operations blocked
        vm.prank(users[1]);
        vm.expectRevert();
        vault.deposit{value: 1 ether}(0, 6001, emptyProof);

        vm.warp(block.timestamp + 2 hours);
        IAegisVault.Position memory pos = vault.getPosition(users[0]);
        vm.prank(users[0]);
        vm.expectRevert();
        vault.withdraw(pos.shares, 0, 6002, emptyProof);

        // Unpause
        vault.unpause();

        // Operations resume
        vm.prank(users[1]);
        vault.deposit{value: 1 ether}(0, 6003, emptyProof);
    }

    // ================================================================
    //       SCENARIO 7: Share Math Integrity Under Load
    // ================================================================

    /// @notice Verify share math remains accurate with many users and operations
    function test_scenario_shareMathIntegrity() public {
        uint256 totalDeposited;

        // 10 users deposit different amounts
        for (uint256 i = 0; i < 10; i++) {
            uint256 amount = (i + 1) * 0.5 ether;
            vm.prank(users[i]);
            vault.deposit{value: amount}(0, i + 800, emptyProof);
            totalDeposited += amount;
        }
        // Total: 0.5+1+1.5+2+2.5+3+3.5+4+4.5+5 = 27.5 ETH
        assertEq(vault.getTotalAssets(), totalDeposited, "Total assets should match deposits");

        // Advance past hold period
        vm.warp(block.timestamp + 2 hours);

        // Verify each user's share value is proportional to their deposit
        for (uint256 i = 0; i < 10; i++) {
            IAegisVault.Position memory pos = vault.getPosition(users[i]);
            uint256 assetValue = vault.convertToAssets(pos.shares);
            uint256 deposited = (i + 1) * 0.5 ether;
            // Should be approximately equal (small rounding from virtual offset)
            assertApproxEqRel(assetValue, deposited, 0.01e18, "Share value should track deposit");
        }

        // First 5 users withdraw
        for (uint256 i = 0; i < 5; i++) {
            IAegisVault.Position memory pos = vault.getPosition(users[i]);
            uint256 balBefore = users[i].balance;
            vm.prank(users[i]);
            vault.withdraw(pos.shares, 0, 0, emptyProof);
            uint256 received = users[i].balance - balBefore;
            uint256 deposited = (i + 1) * 0.5 ether;
            assertApproxEqRel(received, deposited, 0.01e18, "Withdrawal should return ~deposit");
        }

        // Remaining users' share values should be unchanged
        for (uint256 i = 5; i < 10; i++) {
            IAegisVault.Position memory pos = vault.getPosition(users[i]);
            uint256 assetValue = vault.convertToAssets(pos.shares);
            uint256 deposited = (i + 1) * 0.5 ether;
            assertApproxEqRel(assetValue, deposited, 0.01e18, "Remaining share values preserved");
        }
    }

    // ================================================================
    //                    HELPER FUNCTIONS
    // ================================================================

    function _sendYieldReport(uint256 confidence) internal {
        reportNonce++;
        bytes memory report = abi.encodePacked(
            bytes1(0x01),
            abi.encode(confidence, reportNonce)
        );
        forwarder.deliverReport(address(vault), YIELD_WORKFLOW_ID, WF_NAME, WF_OWNER, report);
    }

    function _sendRiskReport(bool shouldActivate, uint256 riskScore) internal {
        reportNonce++;
        bytes memory report = abi.encodePacked(
            bytes1(0x02),
            abi.encode(shouldActivate, riskScore, reportNonce)
        );
        forwarder.deliverReport(address(vault), RISK_WORKFLOW_ID, WF_NAME, WF_OWNER, report);
    }
}
