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
import {IWorldIdGate} from "../../src/interfaces/IWorldIdGate.sol";
import {MockForwarder} from "../helpers/MockForwarder.sol";
import {MockCCIPRouter} from "../helpers/MockCCIPRouter.sol";
import {MockWorldId} from "../helpers/MockWorldId.sol";
import {TestConstants} from "../helpers/TestConstants.sol";

/// @title DeploymentVerification - Cyfrin DevOps-style deployment verification tests
/// @notice Simulates the full Deploy.s.sol flow on Anvil and verifies every cross-reference,
///         access control setting, and initial state matches production expectations.
///         This catches misconfigured deployments before they hit mainnet.
contract DeploymentVerificationTest is Test {
    // ================================================================
    //                    CONTRACT INSTANCES
    // ================================================================

    AegisVault public vault;
    RiskRegistry public registry;
    StrategyRouter public router;
    WorldIdGate public worldIdGate;
    MockForwarder public forwarder;
    MockCCIPRouter public ccipRouter;
    MockWorldId public mockWorldId;

    address public deployer;
    address public aavePool;

    uint64 constant SEPOLIA_CHAIN_SELECTOR = 16015286601757825753;
    uint64 constant BASE_SEPOLIA_CHAIN_SELECTOR = 10344971235874465080;

    bytes32 constant YIELD_WORKFLOW_ID = bytes32(uint256(1));
    bytes32 constant RISK_WORKFLOW_ID = bytes32(uint256(2));
    bytes32 constant VAULT_WORKFLOW_ID = bytes32(uint256(3));

    /// @notice Mirror the full Deploy.s.sol flow exactly
    function setUp() public {
        deployer = address(this);
        aavePool = address(0xBE5E5728dB7F0E23E20B87E3737445796b272484);

        // Deploy mocks (equivalent to Anvil infrastructure)
        forwarder = new MockForwarder();
        ccipRouter = new MockCCIPRouter();
        mockWorldId = new MockWorldId();

        // Deploy core contracts (mirrors Deploy.s.sol steps 1-4)
        worldIdGate = new WorldIdGate(address(mockWorldId), 1, "aegis-vault", 24 hours);
        registry = new RiskRegistry();
        router = new StrategyRouter(address(ccipRouter));
        vault = new AegisVault(address(forwarder));

        // Wire cross-references (mirrors Deploy.s.sol step 5)
        vault.setRiskRegistry(address(registry));
        vault.setStrategyRouter(address(router));
        vault.setWorldIdGate(address(worldIdGate));

        // Authorization setup
        worldIdGate.registerVault(address(vault));
        registry.registerVault(address(vault));
        registry.setSentinelAuthorization(deployer, true);
        router.setVault(address(vault));
        router.setRiskRegistry(address(registry));

        // CCIP chains (mirrors Deploy.s.sol step 6)
        router.setAllowedChain(SEPOLIA_CHAIN_SELECTOR, true);
        router.setAllowedChain(BASE_SEPOLIA_CHAIN_SELECTOR, true);
        router.setChainReceiver(SEPOLIA_CHAIN_SELECTOR, address(router));
        router.setChainReceiver(BASE_SEPOLIA_CHAIN_SELECTOR, address(router));

        // Protocol registration (mirrors Deploy.s.sol step 7)
        registry.addProtocol(aavePool, "Aave V3 Sepolia");

        // Workflow prefix binding
        vault.setWorkflowPrefix(YIELD_WORKFLOW_ID, bytes1(0x01));
        vault.setWorkflowPrefix(RISK_WORKFLOW_ID, bytes1(0x02));
        vault.setWorkflowPrefix(VAULT_WORKFLOW_ID, bytes1(0x03));

        // Complete setup (mirrors Deploy.s.sol step 8)
        vault.completeInitialSetup();
    }

    // ================================================================
    //         DEPLOYMENT ARTIFACT VERIFICATION (Cyfrin DevOps)
    // ================================================================

    /// @notice Verify all contracts deployed to non-zero addresses
    function test_deployment_allContractsDeployed() public view {
        assertTrue(address(vault) != address(0), "Vault not deployed");
        assertTrue(address(registry) != address(0), "Registry not deployed");
        assertTrue(address(router) != address(0), "Router not deployed");
        assertTrue(address(worldIdGate) != address(0), "WorldIdGate not deployed");
        assertTrue(address(forwarder) != address(0), "Forwarder not deployed");
        assertTrue(address(ccipRouter) != address(0), "CCIPRouter not deployed");
    }

    /// @notice Verify all contracts have code (not EOA)
    function test_deployment_allContractsHaveCode() public view {
        assertGt(address(vault).code.length, 0, "Vault has no code");
        assertGt(address(registry).code.length, 0, "Registry has no code");
        assertGt(address(router).code.length, 0, "Router has no code");
        assertGt(address(worldIdGate).code.length, 0, "WorldIdGate has no code");
    }

    // ================================================================
    //          CROSS-REFERENCE VERIFICATION
    // ================================================================

    /// @notice Verify AegisVault -> RiskRegistry reference
    function test_crossRef_vaultToRiskRegistry() public view {
        assertEq(vault.riskRegistry(), address(registry), "Vault -> Registry mismatch");
    }

    /// @notice Verify AegisVault -> StrategyRouter reference
    function test_crossRef_vaultToStrategyRouter() public view {
        assertEq(vault.strategyRouter(), address(router), "Vault -> Router mismatch");
    }

    /// @notice Verify AegisVault -> WorldIdGate reference
    function test_crossRef_vaultToWorldIdGate() public view {
        assertEq(vault.worldIdGate(), address(worldIdGate), "Vault -> WorldIdGate mismatch");
    }

    /// @notice Verify StrategyRouter -> AegisVault reference
    function test_crossRef_routerToVault() public view {
        assertEq(router.vault(), address(vault), "Router -> Vault mismatch");
    }

    /// @notice Verify RiskRegistry authorized vault
    function test_crossRef_registryAuthorizesVault() public view {
        assertTrue(registry.isAuthorizedVault(address(vault)), "Vault not authorized in Registry");
    }

    /// @notice Verify WorldIdGate authorized vault
    function test_crossRef_worldIdAuthorizesVault() public view {
        assertTrue(worldIdGate.isAuthorizedVault(address(vault)), "Vault not authorized in WorldIdGate");
    }

    // ================================================================
    //           OWNERSHIP VERIFICATION
    // ================================================================

    /// @notice Verify all contracts owned by deployer
    function test_ownership_allContractsOwnedByDeployer() public view {
        assertEq(vault.owner(), deployer, "Vault owner mismatch");
        assertEq(registry.owner(), deployer, "Registry owner mismatch");
        assertEq(router.owner(), deployer, "Router owner mismatch");
        assertEq(worldIdGate.owner(), deployer, "WorldIdGate owner mismatch");
    }

    // ================================================================
    //           INITIAL STATE VERIFICATION
    // ================================================================

    /// @notice Verify vault is setup complete
    function test_initialState_vaultSetupComplete() public view {
        assertTrue(vault.isSetupComplete(), "Vault setup not complete");
    }

    /// @notice Verify vault initial parameters
    function test_initialState_vaultDefaults() public view {
        assertEq(vault.minDeposit(), 0.001 ether, "Min deposit mismatch");
        assertEq(vault.minHoldPeriod(), 1 hours, "Min hold period mismatch");
        assertEq(vault.getTotalAssets(), 0, "Total assets should be 0");
        assertEq(vault.totalShares(), 0, "Total shares should be 0");
        assertFalse(vault.isCircuitBreakerActive(), "CB should be inactive");
    }

    /// @notice Verify registry initial parameters
    function test_initialState_registryDefaults() public view {
        assertEq(registry.riskThreshold(), 7000, "Risk threshold mismatch");
        assertEq(registry.maxActivationsPerWindow(), 3, "Max activations mismatch");
        assertEq(registry.autoDeactivationPeriod(), 72 hours, "Auto deactivation mismatch");
        assertFalse(registry.isCircuitBreakerActive(), "CB should be inactive");
    }

    /// @notice Verify protocol is monitored
    function test_initialState_protocolMonitored() public view {
        IRiskRegistry.RiskAssessment memory assessment = registry.getRiskAssessment(aavePool);
        assertTrue(assessment.isMonitored, "Aave pool should be monitored");
        assertEq(assessment.score, 0, "Initial score should be 0");
    }

    /// @notice Verify CCIP chain configuration
    function test_initialState_ccipChainsConfigured() public view {
        assertTrue(router.isChainAllowed(SEPOLIA_CHAIN_SELECTOR), "Sepolia not allowed");
        assertTrue(router.isChainAllowed(BASE_SEPOLIA_CHAIN_SELECTOR), "Base Sepolia not allowed");
        assertEq(router.getChainReceiver(SEPOLIA_CHAIN_SELECTOR), address(router), "Sepolia receiver mismatch");
        assertEq(router.getChainReceiver(BASE_SEPOLIA_CHAIN_SELECTOR), address(router), "Base Sepolia receiver mismatch");
    }

    /// @notice Verify workflow prefix bindings
    function test_initialState_workflowPrefixBindings() public view {
        assertEq(vault.getWorkflowPrefix(YIELD_WORKFLOW_ID), bytes1(0x01), "Yield prefix mismatch");
        assertEq(vault.getWorkflowPrefix(RISK_WORKFLOW_ID), bytes1(0x02), "Risk prefix mismatch");
        assertEq(vault.getWorkflowPrefix(VAULT_WORKFLOW_ID), bytes1(0x03), "Vault-op prefix mismatch");
    }

    // ================================================================
    //      POST-DEPLOYMENT OPERATIONAL SMOKE TESTS
    // ================================================================

    /// @notice Verify deposits work after deployment
    function test_postDeploy_depositWorks() public {
        address user = makeAddr("smokeUser");
        vm.deal(user, 10 ether);

        vm.prank(user);
        vault.deposit{value: 1 ether}(0, 0, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);

        IAegisVault.Position memory pos = vault.getPosition(user);
        assertGt(pos.shares, 0, "Deposit failed: no shares minted");
        assertEq(vault.getTotalAssets(), 1 ether, "Total assets mismatch after deposit");
    }

    /// @notice Verify CRE report delivery works after deployment
    function test_postDeploy_reportDeliveryWorks() public {
        bytes memory yieldReport = abi.encodePacked(bytes1(0x01), abi.encode(uint256(7500)));
        forwarder.deliverReport(
            address(vault),
            YIELD_WORKFLOW_ID,
            bytes10("yield_scan"),
            address(0xCAFE),
            yieldReport
        );
        // No revert = success
    }

    /// @notice Verify risk score updates work after deployment
    function test_postDeploy_riskScoreUpdateWorks() public {
        registry.updateRiskScore(aavePool, 5000, bytes32(uint256(99)));

        IRiskRegistry.RiskAssessment memory assessment = registry.getRiskAssessment(aavePool);
        assertEq(assessment.score, 5000, "Risk score not updated");
    }

    /// @notice Verify circuit breaker can be activated after deployment
    function test_postDeploy_circuitBreakerActivation() public {
        registry.activateCircuitBreaker(bytes32(uint256(1)));
        assertTrue(registry.isCircuitBreakerActive(), "CB should be active");

        registry.deactivateCircuitBreaker();
        assertFalse(registry.isCircuitBreakerActive(), "CB should be inactive");
    }

    // ================================================================
    //      DEPLOYMENT SECURITY VERIFICATION
    // ================================================================

    /// @notice Verify non-owner cannot modify critical settings
    function test_security_nonOwnerCannotModifyVault() public {
        address attacker = makeAddr("attacker");

        vm.startPrank(attacker);

        vm.expectRevert();
        vault.setRiskRegistry(attacker);

        vm.expectRevert();
        vault.setStrategyRouter(attacker);

        vm.expectRevert();
        vault.setWorldIdGate(attacker);

        vm.expectRevert();
        vault.pause();

        vm.stopPrank();
    }

    /// @notice Verify non-owner cannot modify registry
    function test_security_nonOwnerCannotModifyRegistry() public {
        address attacker = makeAddr("attacker");

        vm.startPrank(attacker);

        vm.expectRevert();
        registry.setThreshold(9000);

        vm.expectRevert();
        registry.addProtocol(attacker, "evil");

        vm.expectRevert();
        registry.pause();

        vm.stopPrank();
    }

    /// @notice Verify forwarder is properly set (not zero)
    function test_security_forwarderNotZero() public view {
        address fwd = vault.getForwarderAddress();
        assertTrue(fwd != address(0), "Forwarder is zero - INSECURE");
    }

    /// @notice Verify double setup is prevented
    function test_security_doubleSetupPrevented() public {
        vm.expectRevert();
        vault.completeInitialSetup();
    }
}
