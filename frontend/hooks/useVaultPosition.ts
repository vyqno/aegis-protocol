"use client";

import { useReadContract } from "thirdweb/react";
import { useActiveAccount } from "thirdweb/react";
import { getVaultContract } from "@/lib/contracts";

const vaultContract = getVaultContract();

export interface VaultPosition {
  shares: bigint;
  depositTimestamp: bigint;
  depositAmount: bigint;
}

export function useVaultPosition() {
  const account = useActiveAccount();

  const position = useReadContract({
    contract: vaultContract,
    method:
      "function getPosition(address user) view returns ((uint256 shares, uint256 depositTimestamp, uint256 depositAmount))",
    params: [account?.address || "0x0000000000000000000000000000000000000000"],
    queryOptions: {
      enabled: !!account,
      refetchInterval: 15_000,
    },
  });

  const positionData = position.data as VaultPosition | undefined;

  const currentValue = useReadContract({
    contract: vaultContract,
    method:
      "function convertToAssets(uint256 shares) view returns (uint256 assets)",
    params: [positionData?.shares || 0n],
    queryOptions: {
      enabled: !!positionData && positionData.shares > 0n,
      refetchInterval: 15_000,
    },
  });

  return {
    position: positionData,
    currentValue: currentValue.data as bigint | undefined,
    isLoading: position.isLoading,
    refetch: position.refetch,
  };
}
