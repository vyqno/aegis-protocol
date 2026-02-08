// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {StrategyRouter} from "../../src/core/StrategyRouter.sol";
import {IStrategyRouter} from "../../src/interfaces/IStrategyRouter.sol";
import {MockCCIPRouter} from "../helpers/MockCCIPRouter.sol";
import {TestConstants} from "../helpers/TestConstants.sol";

/// @title StrategyRouterFuzzTest - Fuzz tests for allocations, transfer limits, nonces
contract StrategyRouterFuzzTest is Test {
    StrategyRouter public router;
    MockCCIPRouter public ccipRouter;

    address public vaultAddr;
    uint64 constant CHAIN_A = TestConstants.SEPOLIA_CHAIN_SELECTOR;
    uint64 constant CHAIN_B = TestConstants.BASE_SEPOLIA_CHAIN_SELECTOR;

    function setUp() public {
        ccipRouter = new MockCCIPRouter();
        router = new StrategyRouter(address(ccipRouter));
        vaultAddr = makeAddr("vault");

        router.setVault(vaultAddr);
        router.setAllowedChain(CHAIN_A, true);
        router.setAllowedChain(CHAIN_B, true);
        router.setChainReceiver(CHAIN_A, makeAddr("receiverA"));
        router.setChainReceiver(CHAIN_B, makeAddr("receiverB"));

        // Set vault value for transfer limit calculations
        vm.prank(vaultAddr);
        router.updateTotalVaultValue(100 ether);

        // Fund router for fees
        vm.deal(address(router), 10 ether);
    }

    // ================================================================
    //               ALLOCATION FUZZ TESTS
    // ================================================================

    function testFuzz_setTargetAllocations_valid(uint256 allocA, uint256 allocB) public {
        allocA = bound(allocA, 0, 5000);
        allocB = bound(allocB, 0, 10_000 - allocA);

        uint64[] memory chains = new uint64[](2);
        uint256[] memory allocs = new uint256[](2);
        chains[0] = CHAIN_A;
        chains[1] = CHAIN_B;
        allocs[0] = allocA;
        allocs[1] = allocB;

        router.setTargetAllocations(chains, allocs);

        // INVARIANT: Sum of allocations <= 10000 bps
        assertLe(
            router.getTargetAllocation(CHAIN_A) + router.getTargetAllocation(CHAIN_B),
            10_000,
            "Total allocation must be <= 100%"
        );
    }

    function testFuzz_setTargetAllocations_reverts_exceeds_max(uint256 allocA, uint256 allocB) public {
        allocA = bound(allocA, 5001, 10_000);
        allocB = bound(allocB, 10_001 - allocA, 10_000);

        uint64[] memory chains = new uint64[](2);
        uint256[] memory allocs = new uint256[](2);
        chains[0] = CHAIN_A;
        chains[1] = CHAIN_B;
        allocs[0] = allocA;
        allocs[1] = allocB;

        vm.expectRevert();
        router.setTargetAllocations(chains, allocs);
    }

    // ================================================================
    //             CUMULATIVE TRANSFER LIMIT FUZZ
    // ================================================================

    function testFuzz_bridgeAssets_within_limit(uint256 amount) public {
        // Default: 20% of 100 ETH = 20 ETH max per window
        amount = bound(amount, 0.001 ether, 19 ether);

        address receiver = makeAddr("receiver");
        uint256 fee = ccipRouter.fixedFee();

        vm.deal(vaultAddr, fee);
        vm.prank(vaultAddr);
        router.bridgeAssets{value: fee}(CHAIN_A, receiver, amount);

        // Should succeed - under limit
        uint256 remaining = router.getRemainingTransferBudget();
        assertGt(remaining, 0, "Should have remaining budget");
    }

    function testFuzz_bridgeAssets_cumulative_exceeds_limit(uint256 amount1, uint256 amount2) public {
        // Total vault value = 100 ETH, max = 20%
        uint256 maxTransfer = 20 ether;
        amount1 = bound(amount1, maxTransfer / 2 + 1, maxTransfer);
        amount2 = bound(amount2, maxTransfer / 2 + 1, maxTransfer);
        // Ensure sum exceeds limit
        vm.assume(amount1 + amount2 > maxTransfer);

        address receiver = makeAddr("receiver");
        uint256 fee = ccipRouter.fixedFee();

        // First transfer should succeed (under limit)
        if (amount1 <= maxTransfer) {
            vm.deal(vaultAddr, fee);
            vm.prank(vaultAddr);
            router.bridgeAssets{value: fee}(CHAIN_A, receiver, amount1);

            // Second should fail if cumulative exceeds limit
            vm.deal(vaultAddr, fee);
            vm.prank(vaultAddr);
            vm.expectRevert();
            router.bridgeAssets{value: fee}(CHAIN_A, receiver, amount2);
        }
    }

    // ================================================================
    //                   NONCE FUZZ TESTS
    // ================================================================

    function testFuzz_nonce_monotonically_increasing(uint256 numTransfers) public {
        numTransfers = bound(numTransfers, 1, 10);

        address receiver = makeAddr("receiver");
        uint256 fee = ccipRouter.fixedFee();
        uint256 smallAmount = 0.01 ether;

        // Set high limit so we don't hit it
        router.setMaxCumulativeTransferBps(10_000);

        uint256 lastNonce = router.getCurrentNonce();

        for (uint256 i = 0; i < numTransfers; i++) {
            vm.deal(vaultAddr, fee);
            vm.prank(vaultAddr);
            router.bridgeAssets{value: fee}(CHAIN_A, receiver, smallAmount);

            uint256 currentNonce = router.getCurrentNonce();
            assertGt(currentNonce, lastNonce, "Nonce must strictly increase");
            lastNonce = currentNonce;
        }
    }

    // ================================================================
    //            STRATEGY EXECUTION FUZZ TESTS
    // ================================================================

    function testFuzz_executeStrategy_valid_params(uint256 amount) public {
        amount = bound(amount, 1, 100 ether);

        IStrategyRouter.StrategyParams memory params = IStrategyRouter.StrategyParams({
            targetProtocol: makeAddr("aave"),
            destinationChainSelector: CHAIN_A,
            amount: amount,
            strategyData: "",
            actionType: bytes1(0x01)
        });

        vm.prank(vaultAddr);
        router.executeStrategy(params, bytes32(uint256(1)));
    }

    function testFuzz_executeStrategy_reverts_zero_amount() public {
        IStrategyRouter.StrategyParams memory params = IStrategyRouter.StrategyParams({
            targetProtocol: makeAddr("aave"),
            destinationChainSelector: CHAIN_A,
            amount: 0,
            strategyData: "",
            actionType: bytes1(0x01)
        });

        vm.prank(vaultAddr);
        vm.expectRevert(IStrategyRouter.ZeroAmount.selector);
        router.executeStrategy(params, bytes32(uint256(1)));
    }
}
