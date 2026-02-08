// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AegisVault} from "../../src/core/AegisVault.sol";
import {StrategyRouter} from "../../src/core/StrategyRouter.sol";
import {IStrategyRouter} from "../../src/interfaces/IStrategyRouter.sol";
import {MockForwarder} from "../helpers/MockForwarder.sol";
import {MockCCIPRouter} from "../helpers/MockCCIPRouter.sol";
import {TestConstants} from "../helpers/TestConstants.sol";

/// @title VaultRouterIntegrationTest - Integration tests for AegisVault <-> StrategyRouter
/// @dev Tests cross-chain bridging flow, CCIP validation, and transfer limits
contract VaultRouterIntegrationTest is Test {
    AegisVault public vault;
    StrategyRouter public router;
    MockForwarder public forwarder;
    MockCCIPRouter public ccipRouter;

    address public user1;
    uint64 constant CHAIN_A = TestConstants.SEPOLIA_CHAIN_SELECTOR;
    uint256[8] emptyProof;

    function setUp() public {
        user1 = makeAddr("user1");

        forwarder = new MockForwarder();
        ccipRouter = new MockCCIPRouter();
        vault = new AegisVault(address(forwarder));
        router = new StrategyRouter(address(ccipRouter));

        // Wire contracts
        vault.setStrategyRouter(address(router));
        vault.setWorkflowPrefix(bytes32(uint256(1)), bytes1(0x01));
        vault.completeInitialSetup();

        router.setVault(address(vault));
        router.setAllowedChain(CHAIN_A, true);
        router.setChainReceiver(CHAIN_A, address(router)); // Self for testing

        vm.deal(user1, 100 ether);
        vm.deal(address(router), 10 ether);
    }

    // ================================================================
    //              STRATEGY EXECUTION TESTS
    // ================================================================

    function test_vault_owner_can_execute_strategy_via_router() public {
        // Owner triggers strategy via router
        IStrategyRouter.StrategyParams memory params = IStrategyRouter.StrategyParams({
            targetProtocol: makeAddr("aave"),
            destinationChainSelector: CHAIN_A,
            amount: 1 ether,
            strategyData: "",
            actionType: bytes1(0x01)
        });

        router.executeStrategy(params, bytes32(uint256(1)));
    }

    // ================================================================
    //              CCIP SOURCE VALIDATION TESTS
    // ================================================================

    /// @notice Test F: CCIP from non-whitelisted chain must revert
    function test_ccipReceive_reverts_from_invalid_chain() public {
        uint64 invalidChain = 99999;
        bytes memory payload = abi.encode(uint8(0x01), uint256(1), uint64(1), address(0), uint256(0), bytes(""));

        vm.expectRevert();
        ccipRouter.simulateDelivery(address(router), invalidChain, address(router), payload);
    }

    /// @notice Test F: CCIP from wrong sender on correct chain must revert
    function test_ccipReceive_reverts_from_invalid_sender() public {
        address wrongSender = makeAddr("wrongSender");
        bytes memory payload = abi.encode(uint8(0x01), uint256(1), uint64(1), address(0), uint256(0), bytes(""));

        vm.expectRevert();
        ccipRouter.simulateDelivery(address(router), CHAIN_A, wrongSender, payload);
    }

    /// @notice Valid CCIP message from correct chain and sender
    function test_ccipReceive_succeeds_from_valid_source() public {
        address validSender = address(router); // Set in setUp
        bytes memory payload = abi.encode(uint8(0x01), uint256(1), uint64(1), address(0), uint256(0), bytes(""));

        ccipRouter.simulateDelivery(address(router), CHAIN_A, validSender, payload);
    }

    // ================================================================
    //             TRANSFER LIMIT INTEGRATION TESTS
    // ================================================================

    function test_bridgeAssets_within_cumulative_limit() public {
        // Set vault value
        router.updateTotalVaultValue(100 ether);

        // Default: 20% of 100 ETH = 20 ETH max
        uint256 fee = ccipRouter.fixedFee();

        vm.deal(address(vault), fee);
        vm.prank(address(vault));
        router.bridgeAssets{value: fee}(CHAIN_A, makeAddr("receiver"), 10 ether);

        assertGt(router.getRemainingTransferBudget(), 0, "Should have remaining budget");
    }

    function test_bridgeAssets_reverts_exceeding_cumulative_limit() public {
        router.updateTotalVaultValue(100 ether);
        uint256 fee = ccipRouter.fixedFee();

        // Try to bridge more than 20% of TVL
        vm.deal(address(vault), fee);
        vm.prank(address(vault));
        vm.expectRevert();
        router.bridgeAssets{value: fee}(CHAIN_A, makeAddr("receiver"), 25 ether);
    }

    // ================================================================
    //              NONCE ORDERING TESTS
    // ================================================================

    function test_ccip_nonce_sequential_ordering() public {
        address validSender = address(router);

        // Nonce 1 succeeds
        bytes memory payload1 = abi.encode(uint8(0x01), uint256(1), uint64(1), address(0), uint256(0), bytes(""));
        ccipRouter.simulateDelivery(address(router), CHAIN_A, validSender, payload1);

        // Nonce 2 succeeds
        bytes memory payload2 = abi.encode(uint8(0x01), uint256(2), uint64(1), address(0), uint256(0), bytes(""));
        ccipRouter.simulateDelivery(address(router), CHAIN_A, validSender, payload2);

        // Replaying nonce 1 should fail
        vm.expectRevert();
        ccipRouter.simulateDelivery(address(router), CHAIN_A, validSender, payload1);
    }

    function test_ccip_nonce_gap_rejected() public {
        address validSender = address(router);

        // Skip nonce 1, try nonce 2 directly - should fail
        bytes memory payload = abi.encode(uint8(0x01), uint256(2), uint64(1), address(0), uint256(0), bytes(""));

        vm.expectRevert();
        ccipRouter.simulateDelivery(address(router), CHAIN_A, validSender, payload);
    }
}
