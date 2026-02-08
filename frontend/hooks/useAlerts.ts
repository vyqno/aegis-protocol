"use client";

import { useContractEvents } from "thirdweb/react";
import { prepareEvent } from "thirdweb";
import { getRiskRegistryContract } from "@/lib/contracts";

const registryContract = getRiskRegistryContract();

const riskAlertEvent = prepareEvent({
  signature:
    "event RiskAlertCreated(address indexed protocol, uint256 score, uint256 threshold, uint256 alertNumber, uint256 timestamp)",
});

const cbActivatedEvent = prepareEvent({
  signature:
    "event CircuitBreakerActivated(address indexed trigger, bytes32 indexed reportId, uint256 timestamp)",
});

const cbDeactivatedEvent = prepareEvent({
  signature:
    "event CircuitBreakerDeactivated(address indexed deactivator, uint256 timestamp)",
});

const MAX_DISPLAYED_ALERTS = 100;

export function useAlerts() {
  const riskAlerts = useContractEvents({
    contract: registryContract,
    events: [riskAlertEvent],
    blockRange: 50000,
  });

  const cbActivations = useContractEvents({
    contract: registryContract,
    events: [cbActivatedEvent],
    blockRange: 50000,
  });

  const cbDeactivations = useContractEvents({
    contract: registryContract,
    events: [cbDeactivatedEvent],
    blockRange: 50000,
  });

  const alerts = (riskAlerts.data || []).slice(0, MAX_DISPLAYED_ALERTS);

  return {
    riskAlerts: alerts,
    cbActivations: cbActivations.data || [],
    cbDeactivations: cbDeactivations.data || [],
    isLoading: riskAlerts.isLoading,
  };
}
