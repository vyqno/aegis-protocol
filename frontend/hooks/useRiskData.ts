"use client";

import { useReadContract } from "thirdweb/react";
import { getRiskRegistryContract } from "@/lib/contracts";

const registryContract = getRiskRegistryContract();

export interface CircuitBreakerState {
  isActive: boolean;
  activatedAt: bigint;
  activationCount: bigint;
  windowStart: bigint;
  lastTriggerReportId: string;
}

export function useRiskData() {
  const circuitBreakerState = useReadContract({
    contract: registryContract,
    method:
      "function getCircuitBreakerState() view returns ((bool isActive, uint256 activatedAt, uint256 activationCount, uint256 windowStart, bytes32 lastTriggerReportId))",
    params: [],
    queryOptions: { refetchInterval: 10_000 },
  });

  const riskThreshold = useReadContract({
    contract: registryContract,
    method: "function riskThreshold() view returns (uint256)",
    params: [],
    queryOptions: { refetchInterval: 30_000 },
  });

  const totalAlerts = useReadContract({
    contract: registryContract,
    method: "function totalAlerts() view returns (uint256)",
    params: [],
    queryOptions: { refetchInterval: 10_000 },
  });

  return {
    circuitBreakerState: circuitBreakerState.data as CircuitBreakerState | undefined,
    riskThreshold: riskThreshold.data as bigint | undefined,
    totalAlerts: totalAlerts.data as bigint | undefined,
    isLoading: circuitBreakerState.isLoading,
  };
}

export function useProtocolRisk(protocolAddress: string) {
  const assessment = useReadContract({
    contract: registryContract,
    method:
      "function getRiskAssessment(address protocol) view returns ((uint256 score, uint256 lastUpdated, bool isMonitored))",
    params: [protocolAddress as `0x${string}`],
    queryOptions: {
      enabled: !!protocolAddress && protocolAddress !== "0x0000000000000000000000000000000000000000",
      refetchInterval: 10_000,
    },
  });

  const isSafe = useReadContract({
    contract: registryContract,
    method: "function isProtocolSafe(address protocol) view returns (bool)",
    params: [protocolAddress as `0x${string}`],
    queryOptions: {
      enabled: !!protocolAddress && protocolAddress !== "0x0000000000000000000000000000000000000000",
      refetchInterval: 10_000,
    },
  });

  return {
    assessment: assessment.data as { score: bigint; lastUpdated: bigint; isMonitored: boolean } | undefined,
    isSafe: isSafe.data as boolean | undefined,
    isLoading: assessment.isLoading,
  };
}
