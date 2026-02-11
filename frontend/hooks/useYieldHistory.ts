"use client";

import { useContractEvents } from "thirdweb/react";
import { getVaultContract } from "@/lib/contracts";

export interface YieldDataPoint {
  timestamp: number;
  vaultYield: number;
  aaveRate: number;
  morphoRate: number;
}

/**
 * Reads real yield history from YieldReportReceived events
 *
 * NOTE: This requires CRE workflows to be deployed and active.
 * Until yield-scanner workflow is running, this will return empty data.
 *
 * To deploy workflows:
 * 1. Request Early Access (available Feb 14+)
 * 2. Run: cre workflow deploy yield-scanner --target staging-settings
 */
export function useYieldHistory(timeRange: "1H" | "6H" | "24H" | "7D" = "24H") {
  const vaultContract = getVaultContract();

  // Calculate block range based on timeRange
  const hoursAgo =
    timeRange === "1H" ? 1
    : timeRange === "6H" ? 6
    : timeRange === "24H" ? 24
    : 168;

  // Sepolia: ~12 second blocks
  const blocksAgo = Math.floor((hoursAgo * 3600) / 12);

  // Read YieldReportReceived events
  const { data: events, isLoading } = useContractEvents({
    contract: vaultContract,
    events: [
      {
        type: "event",
        name: "YieldReportReceived",
        inputs: [
          { name: "reportKey", type: "bytes32", indexed: true },
          { name: "data", type: "bytes", indexed: false },
        ],
      },
    ],
    blockRange: blocksAgo,
  });

  // Transform events to chart data
  const data: YieldDataPoint[] = events?.map((event) => {
    // Decode report data: 0x01 + abi.encode(uint256 confidence)
    // For now, return empty structure until events exist
    return {
      timestamp: Number(event.blockTimestamp) * 1000,
      vaultYield: 0, // Extract from event.data when available
      aaveRate: 0,   // Requires external API
      morphoRate: 0, // Requires external API
    };
  }) || [];

  return {
    data,
    isLoading,
    isEmpty: data.length === 0,
  };
}
