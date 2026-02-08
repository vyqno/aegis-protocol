"use client";

import { useContractEvents } from "thirdweb/react";
import { prepareEvent } from "thirdweb";
import { getVaultContract } from "@/lib/contracts";

const vaultContract = getVaultContract();

const yieldReportEvent = prepareEvent({
  signature:
    "event YieldReportReceived(bytes32 indexed reportKey, bytes data)",
});

const riskReportEvent = prepareEvent({
  signature:
    "event RiskReportReceived(bytes32 indexed reportKey, bool shouldActivate, uint256 riskScore)",
});

const vaultOpEvent = prepareEvent({
  signature:
    "event VaultOperationReceived(bytes32 indexed reportKey, bytes data)",
});

export function useWorkflowEvents() {
  const yieldEvents = useContractEvents({
    contract: vaultContract,
    events: [yieldReportEvent],
    blockRange: 50000,
  });

  const riskEvents = useContractEvents({
    contract: vaultContract,
    events: [riskReportEvent],
    blockRange: 50000,
  });

  const vaultOpEvents = useContractEvents({
    contract: vaultContract,
    events: [vaultOpEvent],
    blockRange: 50000,
  });

  return {
    yieldEvents: yieldEvents.data || [],
    riskEvents: riskEvents.data || [],
    vaultOpEvents: vaultOpEvents.data || [],
    isLoading:
      yieldEvents.isLoading ||
      riskEvents.isLoading ||
      vaultOpEvents.isLoading,
  };
}
