// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {StrategyRouter} from "../../src/core/StrategyRouter.sol";
import {IStrategyRouter} from "../../src/interfaces/IStrategyRouter.sol";
import {MockCCIPRouter} from "../helpers/MockCCIPRouter.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";

/// @title StrategyRouterTest - Unit tests for StrategyRouter
contract StrategyRouterTest is Test {
    StrategyRouter public router;
    MockCCIPRouter public mockCCIP;

    address public owner;
    address public vaultAddr;
    address public unauthorized;
    address public remoteReceiver;

    uint64 constant SEPOLIA_SELECTOR = 16015286601757825753;
    uint64 constant BASE_SEPOLIA_SELECTOR = 10344971235874465080;
    uint64 constant DISALLOWED_CHAIN = 999;

    function setUp() public {
        owner = address(this);
        vaultAddr = makeAddr("vault");
        unauthorized = makeAddr("unauthorized");
        remoteReceiver = makeAddr("remoteReceiver");

        // Deploy
        mockCCIP = new MockCCIPRouter();
        router = new StrategyRouter(address(mockCCIP));

        // Configure
        router.setVault(vaultAddr);
        router.setAllowedChain(BASE_SEPOLIA_SELECTOR, true);
        router.setChainReceiver(BASE_SEPOLIA_SELECTOR, remoteReceiver);
        router.updateTotalVaultValue(100 ether);

        // Fund router for CCIP fees
        vm.deal(address(router), 10 ether);
        vm.deal(vaultAddr, 100 ether);
    }

    // ================================================================
    //                   STRATEGY EXECUTION TESTS
    // ================================================================

    function test_executeStrategy_from_vault() public {
        IStrategyRouter.StrategyParams memory params = IStrategyRouter.StrategyParams({
            targetProtocol: makeAddr("aave"),
            destinationChainSelector: BASE_SEPOLIA_SELECTOR,
            amount: 1 ether,
            strategyData: "",
            actionType: bytes1(0x01)
        });

        vm.prank(vaultAddr);
        router.executeStrategy(params, bytes32(uint256(1)));
    }

    function test_executeStrategy_reverts_from_unauthorized() public {
        IStrategyRouter.StrategyParams memory params = IStrategyRouter.StrategyParams({
            targetProtocol: makeAddr("aave"),
            destinationChainSelector: BASE_SEPOLIA_SELECTOR,
            amount: 1 ether,
            strategyData: "",
            actionType: bytes1(0x01)
        });

        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(IStrategyRouter.CallerNotAuthorized.selector, unauthorized)
        );
        router.executeStrategy(params, bytes32(uint256(1)));
    }

    function test_executeStrategy_reverts_disallowed_chain() public {
        IStrategyRouter.StrategyParams memory params = IStrategyRouter.StrategyParams({
            targetProtocol: makeAddr("aave"),
            destinationChainSelector: DISALLOWED_CHAIN,
            amount: 1 ether,
            strategyData: "",
            actionType: bytes1(0x01)
        });

        vm.prank(vaultAddr);
        vm.expectRevert(
            abi.encodeWithSelector(IStrategyRouter.InvalidChainSelector.selector, DISALLOWED_CHAIN)
        );
        router.executeStrategy(params, bytes32(uint256(1)));
    }

    // ================================================================
    //                   BRIDGE ASSETS TESTS
    // ================================================================

    function test_sendCrossChain_to_allowed_chain() public {
        vm.prank(vaultAddr);
        bytes32 msgId = router.bridgeAssets{value: 0.1 ether}(
            BASE_SEPOLIA_SELECTOR,
            remoteReceiver,
            1 ether
        );

        assertNotEq(msgId, bytes32(0), "Should return valid message ID");
        assertEq(router.getCurrentNonce(), 1, "Nonce should increment");
        assertEq(mockCCIP.getSentMessageCount(), 1, "Should have 1 sent message");
    }

    function test_sendCrossChain_reverts_to_disallowed_chain() public {
        vm.prank(vaultAddr);
        vm.expectRevert(
            abi.encodeWithSelector(IStrategyRouter.InvalidChainSelector.selector, DISALLOWED_CHAIN)
        );
        router.bridgeAssets{value: 0.1 ether}(DISALLOWED_CHAIN, remoteReceiver, 1 ether);
    }

    function test_sendCrossChain_reverts_insufficient_fee() public {
        vm.prank(vaultAddr);
        vm.expectRevert(); // MockCCIPRouter checks fee
        router.bridgeAssets{value: 0.001 ether}(BASE_SEPOLIA_SELECTOR, remoteReceiver, 1 ether);
    }

    function test_sendCrossChain_reverts_exceeding_cumulative_limit() public {
        // Max cumulative = 20% of 100 ETH = 20 ETH per window
        // Try to bridge 25 ETH - should fail
        vm.prank(vaultAddr);
        vm.expectRevert();
        router.bridgeAssets{value: 0.1 ether}(BASE_SEPOLIA_SELECTOR, remoteReceiver, 25 ether);
    }

    function test_cumulativeLimit_allows_within_budget() public {
        // 15 ETH is within 20% of 100 ETH
        vm.prank(vaultAddr);
        router.bridgeAssets{value: 0.1 ether}(BASE_SEPOLIA_SELECTOR, remoteReceiver, 15 ether);

        uint256 remaining = router.getRemainingTransferBudget();
        assertEq(remaining, 5 ether, "Should have 5 ETH remaining");
    }

    function test_cumulativeLimit_resets_after_window() public {
        // Use up 15 ETH of the 20 ETH budget
        vm.prank(vaultAddr);
        router.bridgeAssets{value: 0.1 ether}(BASE_SEPOLIA_SELECTOR, remoteReceiver, 15 ether);

        // Advance past window (24 hours)
        vm.warp(block.timestamp + 25 hours);

        // Should be able to bridge again
        vm.prank(vaultAddr);
        router.bridgeAssets{value: 0.1 ether}(BASE_SEPOLIA_SELECTOR, remoteReceiver, 15 ether);
    }

    // ================================================================
    //                   CCIP RECEIVE TESTS
    // ================================================================

    function test_receiveCrossChain_validates_source_chain() public {
        // Build payload with nonce=1
        bytes memory payload = abi.encode(
            uint8(0x01), uint256(1), uint64(block.chainid), address(0), uint256(0), bytes("")
        );

        // Deliver from allowed chain with correct sender
        mockCCIP.simulateDelivery(
            address(router),
            BASE_SEPOLIA_SELECTOR,
            remoteReceiver,
            payload
        );
        // No revert = success
    }

    function test_receiveCrossChain_rejects_unknown_source() public {
        bytes memory payload = abi.encode(
            uint8(0x01), uint256(1), uint64(block.chainid), address(0), uint256(0), bytes("")
        );

        vm.expectRevert(
            abi.encodeWithSelector(IStrategyRouter.InvalidChainSelector.selector, DISALLOWED_CHAIN)
        );
        mockCCIP.simulateDelivery(
            address(router),
            DISALLOWED_CHAIN,
            remoteReceiver,
            payload
        );
    }

    function test_receiveCrossChain_validates_sender_address() public {
        bytes memory payload = abi.encode(
            uint8(0x01), uint256(1), uint64(block.chainid), address(0), uint256(0), bytes("")
        );

        address wrongSender = makeAddr("wrongSender");
        vm.expectRevert(
            abi.encodeWithSelector(IStrategyRouter.InvalidSourceSender.selector, wrongSender, remoteReceiver)
        );
        mockCCIP.simulateDelivery(
            address(router),
            BASE_SEPOLIA_SELECTOR,
            wrongSender,
            payload
        );
    }

    // ================================================================
    //                   NONCE TESTS
    // ================================================================

    function test_ccip_message_nonce_increments() public {
        assertEq(router.getCurrentNonce(), 0);

        vm.prank(vaultAddr);
        router.bridgeAssets{value: 0.1 ether}(BASE_SEPOLIA_SELECTOR, remoteReceiver, 1 ether);
        assertEq(router.getCurrentNonce(), 1);

        vm.prank(vaultAddr);
        router.bridgeAssets{value: 0.1 ether}(BASE_SEPOLIA_SELECTOR, remoteReceiver, 1 ether);
        assertEq(router.getCurrentNonce(), 2);
    }

    function test_ccip_message_replay_rejected() public {
        bytes memory payload1 = abi.encode(
            uint8(0x01), uint256(1), uint64(block.chainid), address(0), uint256(0), bytes("")
        );

        // First message with nonce 1 succeeds
        mockCCIP.simulateDelivery(address(router), BASE_SEPOLIA_SELECTOR, remoteReceiver, payload1);

        // Replay same nonce should fail (expecting nonce 2 now)
        vm.expectRevert(
            abi.encodeWithSelector(IStrategyRouter.NonceAlreadyUsed.selector, 1)
        );
        mockCCIP.simulateDelivery(address(router), BASE_SEPOLIA_SELECTOR, remoteReceiver, payload1);
    }

    // ================================================================
    //                   TARGET ALLOCATION TESTS
    // ================================================================

    function test_setTargetAllocations_validates_sum() public {
        uint64[] memory chains = new uint64[](2);
        chains[0] = BASE_SEPOLIA_SELECTOR;
        chains[1] = SEPOLIA_SELECTOR;

        uint256[] memory allocs = new uint256[](2);
        allocs[0] = 6000;
        allocs[1] = 4000;

        router.setTargetAllocations(chains, allocs);

        assertEq(router.getTargetAllocation(BASE_SEPOLIA_SELECTOR), 6000);
        assertEq(router.getTargetAllocation(SEPOLIA_SELECTOR), 4000);
    }

    function test_setTargetAllocations_reverts_over_100_percent() public {
        uint64[] memory chains = new uint64[](2);
        chains[0] = BASE_SEPOLIA_SELECTOR;
        chains[1] = SEPOLIA_SELECTOR;

        uint256[] memory allocs = new uint256[](2);
        allocs[0] = 7000;
        allocs[1] = 4000; // Total = 11000 > 10000

        vm.expectRevert(abi.encodeWithSelector(StrategyRouter.AllocationsExceedMax.selector, 11000));
        router.setTargetAllocations(chains, allocs);
    }

    function test_setTargetAllocations_reverts_mismatched_arrays() public {
        uint64[] memory chains = new uint64[](2);
        chains[0] = BASE_SEPOLIA_SELECTOR;
        chains[1] = SEPOLIA_SELECTOR;

        uint256[] memory allocs = new uint256[](1);
        allocs[0] = 5000;

        vm.expectRevert(StrategyRouter.ArrayLengthMismatch.selector);
        router.setTargetAllocations(chains, allocs);
    }

    // ================================================================
    //                   EMERGENCY WITHDRAW TESTS
    // ================================================================

    function test_emergencyWithdrawAll_by_owner_only() public {
        // Fund router for CCIP fee
        vm.deal(address(router), 1 ether);

        vm.expectEmit(true, true, false, false);
        emit StrategyRouter.EmergencyWithdrawInitiated(BASE_SEPOLIA_SELECTOR, owner, block.timestamp);
        router.emergencyWithdrawAll(BASE_SEPOLIA_SELECTOR);
    }

    function test_emergencyWithdrawAll_reverts_from_vault() public {
        vm.prank(vaultAddr);
        vm.expectRevert();
        router.emergencyWithdrawAll(BASE_SEPOLIA_SELECTOR);
    }

    function test_emergencyWithdrawAll_emits_event() public {
        vm.deal(address(router), 1 ether);

        vm.expectEmit(true, true, false, true);
        emit StrategyRouter.EmergencyWithdrawInitiated(BASE_SEPOLIA_SELECTOR, owner, block.timestamp);
        router.emergencyWithdrawAll(BASE_SEPOLIA_SELECTOR);
    }

    // ================================================================
    //                   1INCH SELECTOR TESTS
    // ================================================================

    function test_1inch_selector_whitelist() public {
        bytes4 swapSelector = bytes4(keccak256("swap(address,address,uint256)"));
        router.setSwapSelectorWhitelist(swapSelector, true);
        assertTrue(router.isSwapSelectorAllowed(swapSelector));
    }

    function test_1inch_rejects_disallowed_selector() public view {
        bytes4 dangerousSelector = bytes4(keccak256("transferFrom(address,address,uint256)"));
        assertFalse(router.isSwapSelectorAllowed(dangerousSelector));
    }

    // ================================================================
    //                   FAILED TRANSFER TESTS
    // ================================================================

    function test_failedTransfer_tracking() public {
        // Bridge to create a pending transfer
        vm.prank(vaultAddr);
        bytes32 msgId = router.bridgeAssets{value: 0.1 ether}(
            BASE_SEPOLIA_SELECTOR,
            remoteReceiver,
            1 ether
        );

        // Check pending
        StrategyRouter.PendingTransfer memory pt = router.getPendingTransfer(msgId);
        assertEq(pt.amount, 1 ether);
        assertFalse(pt.completed);
        assertFalse(pt.failed);

        // Mark as failed
        router.markTransferFailed(msgId);

        pt = router.getPendingTransfer(msgId);
        assertTrue(pt.failed);
    }

    // ================================================================
    //                   PAUSABLE TESTS
    // ================================================================

    function test_pause_blocks_strategy_execution() public {
        router.pause();

        IStrategyRouter.StrategyParams memory params = IStrategyRouter.StrategyParams({
            targetProtocol: makeAddr("aave"),
            destinationChainSelector: BASE_SEPOLIA_SELECTOR,
            amount: 1 ether,
            strategyData: "",
            actionType: bytes1(0x01)
        });

        vm.prank(vaultAddr);
        vm.expectRevert();
        router.executeStrategy(params, bytes32(uint256(1)));
    }

    // ================================================================
    //                   ADMIN TESTS
    // ================================================================

    function test_setVault() public {
        address newVault = makeAddr("newVault");
        router.setVault(newVault);
        assertEq(router.vault(), newVault);
    }

    function test_setAllowedChain() public {
        router.setAllowedChain(SEPOLIA_SELECTOR, true);
        assertTrue(router.isChainAllowed(SEPOLIA_SELECTOR));

        router.setAllowedChain(SEPOLIA_SELECTOR, false);
        assertFalse(router.isChainAllowed(SEPOLIA_SELECTOR));
    }

    function test_ownership_is_two_step() public {
        address newOwner = makeAddr("newOwner");
        router.transferOwnership(newOwner);
        assertEq(router.owner(), address(this));

        vm.prank(newOwner);
        router.acceptOwnership();
        assertEq(router.owner(), newOwner);
    }
}
