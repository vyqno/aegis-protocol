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

/// @title CREWorkflowSimulation - End-to-end simulation of all 3 CRE workflows
/// @notice Simulates real-time production behavior:
///         1. Yield Scanner (Cron - every 5 min): reads vault state, AI analysis, writes 0x01 report
///         2. Risk Sentinel (Log - on RiskAlertCreated): evaluates risk, writes 0x02 report
///         3. Vault Manager (HTTP - on-demand): validates operations, writes 0x03 report
///         Tests the full lifecycle as it would run on Chainlink DON nodes.
contract CREWorkflowSimulationTest is Test {
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
    address public user1;
    address public user2;
    address public user3;
    address public aavePool;

    bytes32 constant YIELD_WORKFLOW_ID = bytes32(uint256(1));
    bytes32 constant RISK_WORKFLOW_ID = bytes32(uint256(2));
    bytes32 constant VAULT_WORKFLOW_ID = bytes32(uint256(3));
    bytes10 constant YIELD_WORKFLOW_NAME = bytes10("yield_scan");
    bytes10 constant RISK_WORKFLOW_NAME = bytes10("risk_sent");
    bytes10 constant VAULT_WORKFLOW_NAME = bytes10("vault_mgr");
    address constant WORKFLOW_OWNER = address(0xCAFE);

    uint256[8] emptyProof;

    function setUp() public {
        deployer = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        aavePool = address(0xBE5E5728dB7F0E23E20B87E3737445796b272484);

        // Deploy full infrastructure
        forwarder = new MockForwarder();
        ccipRouter = new MockCCIPRouter();
        mockWorldId = new MockWorldId();

        worldIdGate = new WorldIdGate(address(mockWorldId), 1, "aegis-vault", 24 hours);
        registry = new RiskRegistry();
        router = new StrategyRouter(address(ccipRouter));
        vault = new AegisVault(address(forwarder));

        // Wire everything
        vault.setRiskRegistry(address(registry));
        vault.setStrategyRouter(address(router));
        vault.setWorldIdGate(address(worldIdGate));
        worldIdGate.registerVault(address(vault));
        registry.registerVault(address(vault));
        registry.setSentinelAuthorization(deployer, true);
        router.setVault(address(vault));
        router.setRiskRegistry(address(registry));
        router.setAllowedChain(TestConstants.SEPOLIA_CHAIN_SELECTOR, true);
        router.setChainReceiver(TestConstants.SEPOLIA_CHAIN_SELECTOR, address(router));
        registry.addProtocol(aavePool, "Aave V3");

        // Bind workflows
        vault.setWorkflowPrefix(YIELD_WORKFLOW_ID, bytes1(0x01));
        vault.setWorkflowPrefix(RISK_WORKFLOW_ID, bytes1(0x02));
        vault.setWorkflowPrefix(VAULT_WORKFLOW_ID, bytes1(0x03));

        vault.completeInitialSetup();

        // Fund users
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
    }

    // ================================================================
    //    YIELD SCANNER WORKFLOW SIMULATION (Cron: every 5 min)
    // ================================================================

    /// @notice Simulates yield scanner cron callback:
    ///         1. Read vault state (getTotalAssets, isCircuitBreakerActive, totalShares)
    ///         2. AI returns {action: HOLD/REBALANCE, confidence: 0-10000}
    ///         3. Write signed report with prefix 0x01
    function test_yieldScanner_cronCallback_hold() public {
        // Setup: user deposits so vault has assets
        vm.prank(user1);
        vault.deposit{value: 10 ether}(0, 0, emptyProof);

        // Simulate DON node reading vault state
        uint256 totalAssets = vault.getTotalAssets();
        bool cbActive = vault.isCircuitBreakerActive();
        uint256 totalShares = vault.totalShares();

        assertEq(totalAssets, 10 ether, "Vault should have 10 ETH");
        assertFalse(cbActive, "CB should be inactive");
        assertGt(totalShares, 0, "Should have shares");

        // Simulate Groq AI response: HOLD with 7500 confidence (75%)
        uint256 confidence = 7500;
        bytes memory yieldReport = abi.encodePacked(
            bytes1(0x01),
            abi.encode(confidence)
        );

        // Simulate DON writing signed report via KeystoneForwarder
        vm.expectEmit(false, false, false, false);
        emit IAegisVault.ReportProcessed(bytes1(0x01), bytes32(0));
        forwarder.deliverReport(
            address(vault),
            YIELD_WORKFLOW_ID,
            YIELD_WORKFLOW_NAME,
            WORKFLOW_OWNER,
            yieldReport
        );
    }

    /// @notice Yield scanner skips when circuit breaker is active (production behavior)
    function test_yieldScanner_skipsWhenCircuitBreakerActive() public {
        vm.prank(user1);
        vault.deposit{value: 10 ether}(0, 0, emptyProof);

        // Activate CB via risk report
        _sendRiskReport(true, 9500, 1);

        // DON node checks CB before proceeding
        assertTrue(vault.isCircuitBreakerActive(), "CB should be active");
        // In production, yield scanner returns early. Verify the check works.
    }

    /// @notice Yield scanner skips when vault has no assets
    function test_yieldScanner_skipsWhenNoAssets() public {
        uint256 totalAssets = vault.getTotalAssets();
        assertEq(totalAssets, 0, "Should have no assets");
        // In production, yield scanner returns early. We verify the read works.
    }

    /// @notice Multiple cron ticks with different confidence levels
    function test_yieldScanner_multipleCronTicks() public {
        vm.prank(user1);
        vault.deposit{value: 10 ether}(0, 0, emptyProof);

        // Tick 1: confidence 7500 (5 min mark)
        _sendYieldReport(7500, 1);
        vm.warp(block.timestamp + 5 minutes);

        // Tick 2: confidence 8200 (10 min mark)
        _sendYieldReport(8200, 2);
        vm.warp(block.timestamp + 5 minutes);

        // Tick 3: confidence 6000 (15 min mark)
        _sendYieldReport(6000, 3);
        vm.warp(block.timestamp + 5 minutes);

        // Tick 4: confidence below threshold (4000) - in production, skipped
        // We still test the report delivery works
        _sendYieldReport(4000, 4);
    }

    // ================================================================
    //    RISK SENTINEL WORKFLOW SIMULATION (Log: RiskAlertCreated)
    // ================================================================

    /// @notice Simulates risk sentinel log callback:
    ///         1. Decode RiskAlertCreated event
    ///         2. Idempotency check (is CB already active?)
    ///         3. AI risk assessment
    ///         4. Write 0x02 report if shouldActivate
    function test_riskSentinel_logCallback_activatesCircuitBreaker() public {
        vm.prank(user1);
        vault.deposit{value: 10 ether}(0, 0, emptyProof);

        // Simulate: Registry emits RiskAlertCreated when score exceeds threshold
        registry.updateRiskScore(aavePool, 8000, bytes32(uint256(100)));

        // Risk sentinel sees the alert, evaluates with AI
        // AI returns: shouldActivate=true, riskScore=8500
        _sendRiskReport(true, 8500, 1);

        // Verify CB was activated on vault
        assertTrue(vault.isCircuitBreakerActive(), "Vault CB should be active");
    }

    /// @notice Risk sentinel idempotency: skips if CB already active
    function test_riskSentinel_idempotencyCheck() public {
        vm.prank(user1);
        vault.deposit{value: 10 ether}(0, 0, emptyProof);

        // First risk report activates CB
        _sendRiskReport(true, 9000, 1);
        assertTrue(vault.isCircuitBreakerActive(), "CB should be active after first report");

        // In production, sentinel checks CB before making API call:
        // if (vault.isCircuitBreakerActive()) return; // skip
        bool cbActive = vault.isCircuitBreakerActive();
        assertTrue(cbActive, "Sentinel would skip - CB already active");
    }

    /// @notice Risk sentinel with HOLD response (below threshold)
    function test_riskSentinel_holdResponse() public {
        vm.prank(user1);
        vault.deposit{value: 10 ether}(0, 0, emptyProof);

        // AI returns shouldActivate=false (risk not severe enough)
        _sendRiskReport(false, 5000, 1);
        assertFalse(vault.isCircuitBreakerActive(), "CB should remain inactive for HOLD");
    }

    /// @notice Risk sentinel rate limiting: max 3 activations per hour on registry
    function test_riskSentinel_rateLimiting() public {
        // Activate and deactivate 3 times
        for (uint256 i = 0; i < 3; i++) {
            registry.activateCircuitBreaker(bytes32(i));
            registry.deactivateCircuitBreaker();
        }

        // 4th activation is rate-limited
        vm.expectRevert(
            abi.encodeWithSelector(
                IRiskRegistry.CircuitBreakerRateLimited.selector,
                3,
                3
            )
        );
        registry.activateCircuitBreaker(bytes32(uint256(3)));

        // After 1 hour window resets
        vm.warp(block.timestamp + 1 hours + 1);
        registry.activateCircuitBreaker(bytes32(uint256(4)));
        assertTrue(registry.isCircuitBreakerActive(), "CB should activate after window reset");
    }

    // ================================================================
    //    VAULT MANAGER WORKFLOW SIMULATION (HTTP: on-demand)
    // ================================================================

    /// @notice Simulates vault manager HTTP callback:
    ///         1. Validate payload (operation type, amount, world ID proofs)
    ///         2. Pre-flight checks (CB status, total assets, setup complete)
    ///         3. Write 0x03 report with encoded operation data
    function test_vaultManager_httpCallback_operationReport() public {
        vm.prank(user1);
        vault.deposit{value: 10 ether}(0, 0, emptyProof);

        // Simulate vault manager receiving HTTP request and writing operation report
        bytes memory operationData = abi.encode(
            uint8(0x01),     // operation type: deposit confirmation
            user1,            // user address
            uint256(10 ether) // amount
        );
        bytes memory vaultReport = abi.encodePacked(bytes1(0x03), operationData);

        forwarder.deliverReport(
            address(vault),
            VAULT_WORKFLOW_ID,
            VAULT_WORKFLOW_NAME,
            WORKFLOW_OWNER,
            vaultReport
        );
        // No revert = success
    }

    /// @notice Vault manager pre-flight: CB check blocks operations
    function test_vaultManager_preFlightCBCheck() public {
        vm.prank(user1);
        vault.deposit{value: 10 ether}(0, 0, emptyProof);

        // Activate CB
        _sendRiskReport(true, 9000, 1);

        // In production, vault manager checks CB before writing report:
        bool cbActive = vault.isCircuitBreakerActive();
        assertTrue(cbActive, "Vault manager would reject - CB active");
    }

    /// @notice Vault manager pre-flight: setup check
    function test_vaultManager_preFlightSetupCheck() public {
        bool setupComplete = vault.isSetupComplete();
        assertTrue(setupComplete, "Vault manager pre-flight: setup should be complete");
    }

    // ================================================================
    //    FULL CRE LIFECYCLE: REAL-TIME PRODUCTION SIMULATION
    // ================================================================

    /// @notice Simulates 1 hour of real-time operation across all 3 workflows
    ///         T+0:  Users deposit
    ///         T+5m: Yield scanner tick #1
    ///         T+10m: Yield scanner tick #2
    ///         T+15m: Risk alert triggers risk sentinel
    ///         T+15m: Risk sentinel activates CB
    ///         T+20m: Yield scanner skips (CB active)
    ///         T+25m: Vault manager rejects operations (CB active)
    ///         T+1h+: CB auto-deactivates (72h in production, simulated)
    ///         T+end: Users withdraw
    function test_fullCRELifecycle_oneHourSimulation() public {
        uint256 startTime = block.timestamp;

        // ===== T+0: Users deposit =====
        vm.prank(user1);
        vault.deposit{value: 5 ether}(0, 111, emptyProof);

        vm.prank(user2);
        vault.deposit{value: 3 ether}(0, 222, emptyProof);

        assertEq(vault.getTotalAssets(), 8 ether, "Total assets after deposits");

        // ===== T+5m: Yield scanner tick #1 (HOLD, confidence 6500) =====
        vm.warp(startTime + 5 minutes);
        _sendYieldReport(6500, 1);

        // ===== T+10m: Yield scanner tick #2 (REBALANCE, confidence 8200) =====
        vm.warp(startTime + 10 minutes);
        _sendYieldReport(8200, 2);

        // ===== T+12m: User3 deposits mid-cycle =====
        vm.warp(startTime + 12 minutes);
        vm.prank(user3);
        vault.deposit{value: 2 ether}(0, 333, emptyProof);
        assertEq(vault.getTotalAssets(), 10 ether, "Total assets after user3 deposit");

        // ===== T+15m: Risk alert triggers sentinel =====
        vm.warp(startTime + 15 minutes);
        registry.updateRiskScore(aavePool, 8500, bytes32(uint256(200)));

        // Risk sentinel evaluates and activates CB
        _sendRiskReport(true, 9200, 1);
        assertTrue(vault.isCircuitBreakerActive(), "CB should be active at T+15m");

        // ===== T+20m: Yield scanner checks CB (would skip in production) =====
        vm.warp(startTime + 20 minutes);
        assertTrue(vault.isCircuitBreakerActive(), "CB still active at T+20m");

        // ===== T+25m: Vault manager rejects (CB active) =====
        vm.warp(startTime + 25 minutes);
        assertTrue(vault.isCircuitBreakerActive(), "CB still active at T+25m");

        // Users cannot deposit
        vm.prank(user1);
        vm.expectRevert(IAegisVault.CircuitBreakerActive.selector);
        vault.deposit{value: 1 ether}(0, 444, emptyProof);

        // Users cannot withdraw
        IAegisVault.Position memory pos1 = vault.getPosition(user1);
        vm.prank(user1);
        vm.expectRevert(IAegisVault.CircuitBreakerActive.selector);
        vault.withdraw(pos1.shares, 0, 555, emptyProof);

        // ===== T+73h: CB auto-deactivates =====
        vm.warp(startTime + 73 hours);
        assertFalse(vault.isCircuitBreakerActive(), "CB should auto-deactivate after 72h");

        // ===== T+73h: Users can now withdraw =====
        pos1 = vault.getPosition(user1);
        uint256 user1BalBefore = user1.balance;
        vm.prank(user1);
        vault.withdraw(pos1.shares, 0, 556, emptyProof);
        assertGt(user1.balance, user1BalBefore, "User1 should receive ETH");

        IAegisVault.Position memory pos2 = vault.getPosition(user2);
        vm.prank(user2);
        vault.withdraw(pos2.shares, 0, 557, emptyProof);

        IAegisVault.Position memory pos3 = vault.getPosition(user3);
        vm.prank(user3);
        vault.withdraw(pos3.shares, 0, 558, emptyProof);

        // Verify vault is drained
        assertEq(vault.totalShares(), 0, "All shares should be redeemed");
    }

    /// @notice Simulates concurrent workflow reports arriving in sequence
    function test_concurrentWorkflows_sequentialReports() public {
        vm.prank(user1);
        vault.deposit{value: 10 ether}(0, 0, emptyProof);

        // All three workflows fire in quick succession
        _sendYieldReport(7000, 1);
        _sendRiskReport(false, 4000, 2); // below threshold, HOLD
        _sendVaultOperationReport(user1, 10 ether, 3);

        // All processed successfully, no CB triggered
        assertFalse(vault.isCircuitBreakerActive(), "CB should be inactive");
    }

    /// @notice Verify workflow isolation - wrong workflow cannot send wrong prefix
    function test_workflowIsolation_crossWorkflowRejection() public {
        // Yield workflow (ID=1) tries to send risk prefix (0x02)
        bytes memory fakeRiskReport = abi.encodePacked(
            bytes1(0x02),
            abi.encode(true, uint256(9999))
        );

        vm.expectRevert();
        forwarder.deliverReport(
            address(vault),
            YIELD_WORKFLOW_ID,     // yield workflow
            YIELD_WORKFLOW_NAME,
            WORKFLOW_OWNER,
            fakeRiskReport          // with risk prefix 0x02
        );

        // Risk workflow (ID=2) tries to send vault-op prefix (0x03)
        bytes memory fakeVaultReport = abi.encodePacked(
            bytes1(0x03),
            abi.encode(uint256(1))
        );

        vm.expectRevert();
        forwarder.deliverReport(
            address(vault),
            RISK_WORKFLOW_ID,      // risk workflow
            RISK_WORKFLOW_NAME,
            WORKFLOW_OWNER,
            fakeVaultReport         // with vault-op prefix 0x03
        );
    }

    /// @notice Verify report deduplication across workflows
    function test_reportDedup_sameDataDifferentWorkflows() public {
        // Same encoded data, different prefixes - should both succeed (different dedup keys)
        bytes memory dataPayload = abi.encode(uint256(5000));

        bytes memory yieldReport = abi.encodePacked(bytes1(0x01), dataPayload);
        forwarder.deliverReport(address(vault), YIELD_WORKFLOW_ID, YIELD_WORKFLOW_NAME, WORKFLOW_OWNER, yieldReport);

        // Same data but risk prefix should also succeed (different prefix = different key)
        bytes memory riskReport = abi.encodePacked(bytes1(0x02), abi.encode(false, uint256(5000)));
        forwarder.deliverReport(address(vault), RISK_WORKFLOW_ID, RISK_WORKFLOW_NAME, WORKFLOW_OWNER, riskReport);
    }

    // ================================================================
    //    CCIP CROSS-CHAIN SIMULATION
    // ================================================================

    /// @notice Simulate bridging assets after yield scanner recommends rebalance
    function test_ccipBridge_afterYieldRebalance() public {
        vm.prank(user1);
        vault.deposit{value: 10 ether}(0, 0, emptyProof);

        // Set total vault value for cumulative limits
        router.updateTotalVaultValue(10 ether);

        // After yield scanner says REBALANCE, strategy router bridges
        uint64 destChain = TestConstants.SEPOLIA_CHAIN_SELECTOR;
        uint256 bridgeAmount = 1 ether;

        vm.deal(address(vault), 10 ether); // fund for CCIP fees
        router.bridgeAssets{value: 0.01 ether}(
            destChain,
            address(router),
            bridgeAmount
        );

        assertEq(ccipRouter.getSentMessageCount(), 1, "One CCIP message should be sent");
        assertEq(router.getCurrentNonce(), 1, "Nonce should increment");
    }

    /// @notice Simulate CCIP message reception with sequential nonce validation
    function test_ccipReceive_sequentialNonceValidation() public {
        uint64 sourceChain = TestConstants.SEPOLIA_CHAIN_SELECTOR;

        // Simulate receiving message with nonce 1
        bytes memory payload1 = abi.encode(
            uint8(0x01), uint256(1), uint64(11155111), address(router), uint256(1 ether), bytes("")
        );
        ccipRouter.simulateDelivery(address(router), sourceChain, address(router), payload1);

        // Nonce 2
        bytes memory payload2 = abi.encode(
            uint8(0x01), uint256(2), uint64(11155111), address(router), uint256(2 ether), bytes("")
        );
        ccipRouter.simulateDelivery(address(router), sourceChain, address(router), payload2);

        // Nonce 4 (skipping 3) should fail
        bytes memory payload4 = abi.encode(
            uint8(0x01), uint256(4), uint64(11155111), address(router), uint256(4 ether), bytes("")
        );
        vm.expectRevert(abi.encodeWithSelector(IStrategyRouter.NonceAlreadyUsed.selector, uint256(4)));
        ccipRouter.simulateDelivery(address(router), sourceChain, address(router), payload4);
    }

    /// @notice Simulate cumulative transfer limit enforcement
    function test_ccipBridge_cumulativeTransferLimit() public {
        router.updateTotalVaultValue(10 ether);
        // Default limit: 20% per 24h = 2 ETH

        vm.deal(address(this), 10 ether);

        // First bridge: 1 ETH (within limit)
        router.bridgeAssets{value: 0.01 ether}(
            TestConstants.SEPOLIA_CHAIN_SELECTOR,
            address(router),
            1 ether
        );

        // Second bridge: 1 ETH (exactly at limit)
        router.bridgeAssets{value: 0.01 ether}(
            TestConstants.SEPOLIA_CHAIN_SELECTOR,
            address(router),
            1 ether
        );

        // Third bridge: 0.5 ETH (exceeds limit)
        vm.expectRevert();
        router.bridgeAssets{value: 0.01 ether}(
            TestConstants.SEPOLIA_CHAIN_SELECTOR,
            address(router),
            0.5 ether
        );
    }

    // ================================================================
    //    WORLD ID INTEGRATION WITH CRE WORKFLOWS
    // ================================================================

    /// @notice Full flow: WorldID verify -> deposit -> yield report -> withdraw
    function test_worldId_fullFlowWithCRE() public {
        // Step 1: User verifies with World ID
        vm.prank(user1);
        worldIdGate.verifyIdentity(user1, 12345, 111, emptyProof);
        assertTrue(worldIdGate.isVerified(user1), "User1 should be verified");

        // Step 2: Deposit (vault calls verifyIdentity - idempotent)
        vm.prank(user1);
        vault.deposit{value: 5 ether}(12345, 222, emptyProof);

        // Step 3: Yield scanner processes
        _sendYieldReport(8000, 1);

        // Step 4: Advance past hold period
        vm.warp(block.timestamp + 2 hours);

        // Step 5: Withdraw
        IAegisVault.Position memory pos = vault.getPosition(user1);
        vm.prank(user1);
        vault.withdraw(pos.shares, 12345, 333, emptyProof);

        assertEq(vault.getPosition(user1).shares, 0, "All shares redeemed");
    }

    /// @notice World ID TTL expiry blocks deposit
    function test_worldId_ttlExpiry() public {
        // Verify
        vm.prank(user1);
        worldIdGate.verifyIdentity(user1, 12345, 111, emptyProof);

        // Advance past TTL (24 hours)
        vm.warp(block.timestamp + 25 hours);

        assertFalse(worldIdGate.isVerified(user1), "Verification should be expired");
    }

    // ================================================================
    //                    HELPER FUNCTIONS
    // ================================================================

    function _sendYieldReport(uint256 confidence, uint256 nonce) internal {
        bytes memory report = abi.encodePacked(
            bytes1(0x01),
            abi.encode(confidence, nonce) // unique data per call
        );
        forwarder.deliverReport(
            address(vault),
            YIELD_WORKFLOW_ID,
            YIELD_WORKFLOW_NAME,
            WORKFLOW_OWNER,
            report
        );
    }

    function _sendRiskReport(bool shouldActivate, uint256 riskScore, uint256 nonce) internal {
        bytes memory report = abi.encodePacked(
            bytes1(0x02),
            abi.encode(shouldActivate, riskScore, nonce) // unique data per call
        );
        forwarder.deliverReport(
            address(vault),
            RISK_WORKFLOW_ID,
            RISK_WORKFLOW_NAME,
            WORKFLOW_OWNER,
            report
        );
    }

    function _sendVaultOperationReport(address user, uint256 amount, uint256 nonce) internal {
        bytes memory report = abi.encodePacked(
            bytes1(0x03),
            abi.encode(user, amount, nonce) // unique data per call
        );
        forwarder.deliverReport(
            address(vault),
            VAULT_WORKFLOW_ID,
            VAULT_WORKFLOW_NAME,
            WORKFLOW_OWNER,
            report
        );
    }
}
