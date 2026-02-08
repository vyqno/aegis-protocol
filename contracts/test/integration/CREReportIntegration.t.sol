// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AegisVault} from "../../src/core/AegisVault.sol";
import {IAegisVault} from "../../src/interfaces/IAegisVault.sol";
import {MockForwarder} from "../helpers/MockForwarder.sol";

/// @title CREReportIntegrationTest - Simulated CRE report processing tests
/// @dev Tests report routing by prefix, workflow binding, deduplication, and edge cases
contract CREReportIntegrationTest is Test {
    AegisVault public vault;
    MockForwarder public forwarder;

    bytes32 constant YIELD_WORKFLOW_ID = bytes32(uint256(1));
    bytes32 constant RISK_WORKFLOW_ID = bytes32(uint256(2));
    bytes32 constant VAULT_WORKFLOW_ID = bytes32(uint256(3));
    bytes32 constant UNKNOWN_WORKFLOW_ID = bytes32(uint256(99));
    bytes10 constant TEST_WORKFLOW_NAME = bytes10("test_work");
    address constant TEST_WORKFLOW_OWNER = address(0xCAFE);

    function setUp() public {
        forwarder = new MockForwarder();
        vault = new AegisVault(address(forwarder));

        vault.setWorkflowPrefix(YIELD_WORKFLOW_ID, bytes1(0x01));
        vault.setWorkflowPrefix(RISK_WORKFLOW_ID, bytes1(0x02));
        vault.setWorkflowPrefix(VAULT_WORKFLOW_ID, bytes1(0x03));
        vault.completeInitialSetup();
    }

    // ================================================================
    //               REPORT ROUTING TESTS
    // ================================================================

    function test_yield_report_0x01_routes_correctly() public {
        bytes memory report = abi.encodePacked(bytes1(0x01), abi.encode(uint256(1000)));

        vm.expectEmit(false, false, false, false);
        emit AegisVault.YieldReportReceived(bytes32(0), "");

        forwarder.deliverReport(
            address(vault), YIELD_WORKFLOW_ID, TEST_WORKFLOW_NAME, TEST_WORKFLOW_OWNER, report
        );
    }

    function test_risk_report_0x02_routes_correctly() public {
        bytes memory report = abi.encodePacked(bytes1(0x02), abi.encode(false, uint256(5000)));

        vm.expectEmit(false, false, false, false);
        emit AegisVault.RiskReportReceived(bytes32(0), false, 0);

        forwarder.deliverReport(
            address(vault), RISK_WORKFLOW_ID, TEST_WORKFLOW_NAME, TEST_WORKFLOW_OWNER, report
        );
    }

    function test_vault_report_0x03_routes_correctly() public {
        bytes memory report = abi.encodePacked(bytes1(0x03), abi.encode(uint256(42)));

        vm.expectEmit(false, false, false, false);
        emit AegisVault.VaultOperationReceived(bytes32(0), "");

        forwarder.deliverReport(
            address(vault), VAULT_WORKFLOW_ID, TEST_WORKFLOW_NAME, TEST_WORKFLOW_OWNER, report
        );
    }

    function test_invalid_prefix_reverts() public {
        bytes memory report = abi.encodePacked(bytes1(0x04), abi.encode(uint256(1)));

        // Unknown workflow (no binding) with unknown prefix
        vm.expectRevert();
        forwarder.deliverReport(
            address(vault), UNKNOWN_WORKFLOW_ID, TEST_WORKFLOW_NAME, TEST_WORKFLOW_OWNER, report
        );
    }

    // ================================================================
    //           WORKFLOW-TO-PREFIX BINDING TESTS
    // ================================================================

    function test_yield_workflow_cannot_send_risk_prefix() public {
        bytes memory report = abi.encodePacked(bytes1(0x02), abi.encode(true, uint256(9000)));

        vm.expectRevert();
        forwarder.deliverReport(
            address(vault), YIELD_WORKFLOW_ID, TEST_WORKFLOW_NAME, TEST_WORKFLOW_OWNER, report
        );
    }

    function test_risk_workflow_cannot_send_yield_prefix() public {
        bytes memory report = abi.encodePacked(bytes1(0x01), abi.encode(uint256(500)));

        vm.expectRevert();
        forwarder.deliverReport(
            address(vault), RISK_WORKFLOW_ID, TEST_WORKFLOW_NAME, TEST_WORKFLOW_OWNER, report
        );
    }

    function test_vault_workflow_cannot_send_risk_prefix() public {
        bytes memory report = abi.encodePacked(bytes1(0x02), abi.encode(true, uint256(9000)));

        vm.expectRevert();
        forwarder.deliverReport(
            address(vault), VAULT_WORKFLOW_ID, TEST_WORKFLOW_NAME, TEST_WORKFLOW_OWNER, report
        );
    }

    // ================================================================
    //              DEDUPLICATION TESTS
    // ================================================================

    function test_same_report_rejected_second_time() public {
        bytes memory report = abi.encodePacked(bytes1(0x01), abi.encode(uint256(1000)));

        forwarder.deliverReport(
            address(vault), YIELD_WORKFLOW_ID, TEST_WORKFLOW_NAME, TEST_WORKFLOW_OWNER, report
        );

        vm.expectRevert();
        forwarder.deliverReport(
            address(vault), YIELD_WORKFLOW_ID, TEST_WORKFLOW_NAME, TEST_WORKFLOW_OWNER, report
        );
    }

    function test_different_data_same_prefix_accepted() public {
        bytes memory report1 = abi.encodePacked(bytes1(0x01), abi.encode(uint256(1000)));
        bytes memory report2 = abi.encodePacked(bytes1(0x01), abi.encode(uint256(2000)));

        forwarder.deliverReport(
            address(vault), YIELD_WORKFLOW_ID, TEST_WORKFLOW_NAME, TEST_WORKFLOW_OWNER, report1
        );

        // Different data = different reportKey
        forwarder.deliverReport(
            address(vault), YIELD_WORKFLOW_ID, TEST_WORKFLOW_NAME, TEST_WORKFLOW_OWNER, report2
        );
    }

    // ================================================================
    //            CIRCUIT BREAKER VIA RISK REPORT
    // ================================================================

    function test_risk_report_activates_circuit_breaker() public {
        assertFalse(vault.isCircuitBreakerActive());

        bytes memory report = abi.encodePacked(bytes1(0x02), abi.encode(true, uint256(9500)));

        forwarder.deliverReport(
            address(vault), RISK_WORKFLOW_ID, TEST_WORKFLOW_NAME, TEST_WORKFLOW_OWNER, report
        );

        assertTrue(vault.isCircuitBreakerActive(), "CB should be active after risk report");
    }

    function test_risk_report_false_does_not_activate_circuit_breaker() public {
        bytes memory report = abi.encodePacked(bytes1(0x02), abi.encode(false, uint256(5000)));

        forwarder.deliverReport(
            address(vault), RISK_WORKFLOW_ID, TEST_WORKFLOW_NAME, TEST_WORKFLOW_OWNER, report
        );

        assertFalse(vault.isCircuitBreakerActive(), "CB should not activate on false");
    }

    // ================================================================
    //              EDGE CASE TESTS
    // ================================================================

    function test_report_too_short_reverts() public {
        bytes memory report = abi.encodePacked(bytes1(0x01)); // Only 1 byte

        vm.expectRevert();
        forwarder.deliverReport(
            address(vault), YIELD_WORKFLOW_ID, TEST_WORKFLOW_NAME, TEST_WORKFLOW_OWNER, report
        );
    }

    function test_non_forwarder_cannot_deliver_report() public {
        bytes memory metadata = forwarder.encodeMetadata(
            YIELD_WORKFLOW_ID, TEST_WORKFLOW_NAME, TEST_WORKFLOW_OWNER
        );
        bytes memory report = abi.encodePacked(bytes1(0x01), abi.encode(uint256(500)));

        vm.prank(makeAddr("attacker"));
        vm.expectRevert();
        vault.onReport(metadata, report);
    }
}
