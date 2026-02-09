// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {DevOpsTools} from "@foundry-devops/DevOpsTools.sol";
import {AegisVault} from "../../src/core/AegisVault.sol";
import {RiskRegistry} from "../../src/core/RiskRegistry.sol";
import {StrategyRouter} from "../../src/core/StrategyRouter.sol";
import {WorldIdGate} from "../../src/access/WorldIdGate.sol";
import {IAegisVault} from "../../src/interfaces/IAegisVault.sol";
import {IRiskRegistry} from "../../src/interfaces/IRiskRegistry.sol";

/// @title DeploymentVerification - Cyfrin DevOps post-deployment verification
/// @notice Fetches REAL deployed contract addresses from broadcast artifacts via
///         DevOpsTools.get_most_recent_deployment() and verifies cross-references,
///         ownership, initial state, and smoke tests against LIVE contracts.
/// @dev Usage:
///      1. Start Anvil:  anvil --port 8545
///      2. Deploy:       forge script script/DeployAnvil.s.sol --tc DeployAnvil --rpc-url http://127.0.0.1:8545 --broadcast
///      3. Test:         forge test --match-path "test/deployment/*" --fork-url http://127.0.0.1:8545
contract DeploymentVerificationTest is Test {
    // ================================================================
    //     LIVE CONTRACT INSTANCES (fetched from broadcast artifacts)
    // ================================================================

    AegisVault public vault;
    RiskRegistry public registry;
    StrategyRouter public router;
    WorldIdGate public worldIdGate;

    address public deployer;
    address public forwarderAddr;
    address public aavePool;

    uint64 constant SEPOLIA_CHAIN_SELECTOR = 16015286601757825753;
    uint64 constant BASE_SEPOLIA_CHAIN_SELECTOR = 10344971235874465080;

    bytes32 constant YIELD_WORKFLOW_ID = bytes32(uint256(1));
    bytes32 constant RISK_WORKFLOW_ID = bytes32(uint256(2));
    bytes32 constant VAULT_WORKFLOW_ID = bytes32(uint256(3));

    /// @notice Fetch deployed addresses from broadcast artifacts — NO new deployments
    function setUp() public {
        // DevOpsTools reads broadcast/ dir to find the most recent deployment
        // for each contract name on this chain ID
        vault = AegisVault(
            payable(DevOpsTools.get_most_recent_deployment("AegisVault", block.chainid))
        );
        registry = RiskRegistry(
            DevOpsTools.get_most_recent_deployment("RiskRegistry", block.chainid)
        );
        router = StrategyRouter(
            payable(DevOpsTools.get_most_recent_deployment("StrategyRouter", block.chainid))
        );
        worldIdGate = WorldIdGate(
            DevOpsTools.get_most_recent_deployment("WorldIdGate", block.chainid)
        );

        // Read deployer and forwarder from the live contracts themselves
        deployer = vault.owner();
        forwarderAddr = vault.getForwarderAddress();
        aavePool = address(0xBE5E5728dB7F0E23E20B87E3737445796b272484);
    }

    // ================================================================
    //         DEPLOYMENT ARTIFACT VERIFICATION
    // ================================================================

    function test_deployment_allContractsDeployed() public view {
        assertTrue(address(vault) != address(0), "Vault not deployed");
        assertTrue(address(registry) != address(0), "Registry not deployed");
        assertTrue(address(router) != address(0), "Router not deployed");
        assertTrue(address(worldIdGate) != address(0), "WorldIdGate not deployed");
    }

    function test_deployment_allContractsHaveCode() public view {
        assertGt(address(vault).code.length, 0, "Vault has no code");
        assertGt(address(registry).code.length, 0, "Registry has no code");
        assertGt(address(router).code.length, 0, "Router has no code");
        assertGt(address(worldIdGate).code.length, 0, "WorldIdGate has no code");
    }

    // ================================================================
    //          CROSS-REFERENCE VERIFICATION
    // ================================================================

    function test_crossRef_vaultToRiskRegistry() public view {
        assertEq(vault.riskRegistry(), address(registry), "Vault -> Registry mismatch");
    }

    function test_crossRef_vaultToStrategyRouter() public view {
        assertEq(vault.strategyRouter(), address(router), "Vault -> Router mismatch");
    }

    function test_crossRef_vaultToWorldIdGate() public view {
        assertEq(vault.worldIdGate(), address(worldIdGate), "Vault -> WorldIdGate mismatch");
    }

    function test_crossRef_routerToVault() public view {
        assertEq(router.vault(), address(vault), "Router -> Vault mismatch");
    }

    function test_crossRef_registryAuthorizesVault() public view {
        assertTrue(registry.isAuthorizedVault(address(vault)), "Vault not authorized in Registry");
    }

    function test_crossRef_worldIdAuthorizesVault() public view {
        assertTrue(worldIdGate.isAuthorizedVault(address(vault)), "Vault not authorized in WorldIdGate");
    }

    // ================================================================
    //           OWNERSHIP VERIFICATION
    // ================================================================

    function test_ownership_allContractsOwnedByDeployer() public view {
        assertEq(vault.owner(), deployer, "Vault owner mismatch");
        assertEq(registry.owner(), deployer, "Registry owner mismatch");
        assertEq(router.owner(), deployer, "Router owner mismatch");
        assertEq(worldIdGate.owner(), deployer, "WorldIdGate owner mismatch");
    }

    // ================================================================
    //           INITIAL STATE VERIFICATION
    // ================================================================

    function test_initialState_vaultSetupComplete() public view {
        assertTrue(vault.isSetupComplete(), "Vault setup not complete");
    }

    function test_initialState_vaultDefaults() public view {
        assertEq(vault.minDeposit(), 0.001 ether, "Min deposit mismatch");
        assertEq(vault.minHoldPeriod(), 1 hours, "Min hold period mismatch");
        assertEq(vault.getTotalAssets(), 0, "Total assets should be 0");
        assertEq(vault.totalShares(), 0, "Total shares should be 0");
        assertFalse(vault.isCircuitBreakerActive(), "CB should be inactive");
    }

    function test_initialState_registryDefaults() public view {
        assertEq(registry.riskThreshold(), 7000, "Risk threshold mismatch");
        assertEq(registry.maxActivationsPerWindow(), 3, "Max activations mismatch");
        assertEq(registry.autoDeactivationPeriod(), 72 hours, "Auto deactivation mismatch");
        assertFalse(registry.isCircuitBreakerActive(), "CB should be inactive");
    }

    function test_initialState_protocolMonitored() public view {
        IRiskRegistry.RiskAssessment memory assessment = registry.getRiskAssessment(aavePool);
        assertTrue(assessment.isMonitored, "Aave pool should be monitored");
        assertEq(assessment.score, 0, "Initial score should be 0");
    }

    function test_initialState_ccipChainsConfigured() public view {
        assertTrue(router.isChainAllowed(SEPOLIA_CHAIN_SELECTOR), "Sepolia not allowed");
        assertTrue(router.isChainAllowed(BASE_SEPOLIA_CHAIN_SELECTOR), "Base Sepolia not allowed");
        assertEq(router.getChainReceiver(SEPOLIA_CHAIN_SELECTOR), address(router), "Sepolia receiver mismatch");
        assertEq(router.getChainReceiver(BASE_SEPOLIA_CHAIN_SELECTOR), address(router), "Base Sepolia receiver mismatch");
    }

    function test_initialState_workflowPrefixBindings() public view {
        assertEq(vault.getWorkflowPrefix(YIELD_WORKFLOW_ID), bytes1(0x01), "Yield prefix mismatch");
        assertEq(vault.getWorkflowPrefix(RISK_WORKFLOW_ID), bytes1(0x02), "Risk prefix mismatch");
        assertEq(vault.getWorkflowPrefix(VAULT_WORKFLOW_ID), bytes1(0x03), "Vault-op prefix mismatch");
    }

    // ================================================================
    //      POST-DEPLOYMENT SMOKE TESTS (against LIVE contracts)
    // ================================================================

    function test_postDeploy_depositWorks() public {
        address user = makeAddr("smokeUser");
        vm.deal(user, 10 ether);

        vm.prank(user);
        vault.deposit{value: 1 ether}(0, 0, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);

        IAegisVault.Position memory pos = vault.getPosition(user);
        assertGt(pos.shares, 0, "Deposit failed: no shares minted");
        assertEq(vault.getTotalAssets(), 1 ether, "Total assets mismatch after deposit");
    }

    function test_postDeploy_reportDeliveryWorks() public {
        // Build metadata the same way KeystoneForwarder does
        bytes memory metadata = abi.encodePacked(
            YIELD_WORKFLOW_ID,
            bytes10("yield_scan"),
            address(0xCAFE)
        );
        bytes memory yieldReport = abi.encodePacked(bytes1(0x01), abi.encode(uint256(7500)));

        // Impersonate the REAL deployed forwarder address
        vm.prank(forwarderAddr);
        vault.onReport(metadata, yieldReport);
    }

    function test_postDeploy_riskScoreUpdateWorks() public {
        vm.prank(deployer);
        registry.updateRiskScore(aavePool, 5000, bytes32(uint256(99)));

        IRiskRegistry.RiskAssessment memory assessment = registry.getRiskAssessment(aavePool);
        assertEq(assessment.score, 5000, "Risk score not updated");
    }

    function test_postDeploy_circuitBreakerActivation() public {
        vm.prank(deployer);
        registry.activateCircuitBreaker(bytes32(uint256(1)));
        assertTrue(registry.isCircuitBreakerActive(), "CB should be active");

        vm.prank(deployer);
        registry.deactivateCircuitBreaker();
        assertFalse(registry.isCircuitBreakerActive(), "CB should be inactive");
    }

    // ================================================================
    //      DEPLOYMENT SECURITY VERIFICATION
    // ================================================================

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

    function test_security_forwarderNotZero() public view {
        assertTrue(forwarderAddr != address(0), "Forwarder is zero - INSECURE");
    }

    function test_security_doubleSetupPrevented() public {
        vm.prank(deployer);
        vm.expectRevert();
        vault.completeInitialSetup();
    }
}
