"use client";

import { useReadContract, useSendTransaction } from "thirdweb/react";
import { prepareContractCall, simulateTransaction } from "thirdweb";
import { useActiveAccount } from "thirdweb/react";
import { parseEther } from "viem";
import { getVaultContract } from "@/lib/contracts";
import { useState, useCallback } from "react";

const vaultContract = getVaultContract();

export function useVaultRead() {
  const totalAssets = useReadContract({
    contract: vaultContract,
    method: "function getTotalAssets() view returns (uint256)",
    params: [],
  });

  const circuitBreakerActive = useReadContract({
    contract: vaultContract,
    method: "function isCircuitBreakerActive() view returns (bool)",
    params: [],
  });

  const totalShares = useReadContract({
    contract: vaultContract,
    method: "function totalShares() view returns (uint256)",
    params: [],
  });

  const isSetupComplete = useReadContract({
    contract: vaultContract,
    method: "function isSetupComplete() view returns (bool)",
    params: [],
  });

  const minDeposit = useReadContract({
    contract: vaultContract,
    method: "function minDeposit() view returns (uint256)",
    params: [],
  });

  const owner = useReadContract({
    contract: vaultContract,
    method: "function owner() view returns (address)",
    params: [],
  });

  return {
    totalAssets,
    circuitBreakerActive,
    totalShares,
    isSetupComplete,
    minDeposit,
    owner,
  };
}

export function useVaultDeposit() {
  const account = useActiveAccount();
  const { mutateAsync: sendTx } = useSendTransaction();
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const deposit = useCallback(
    async (
      amountEth: string,
      worldIdRoot: bigint,
      nullifierHash: bigint,
      proof: readonly [bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint]
    ) => {
      if (!account) {
        setError("Wallet not connected");
        return;
      }
      setIsLoading(true);
      setError(null);

      try {
        const tx = prepareContractCall({
          contract: vaultContract,
          method:
            "function deposit(uint256 worldIdRoot, uint256 nullifierHash, uint256[8] proof) payable",
          params: [worldIdRoot, nullifierHash, proof],
          value: parseEther(amountEth),
        });

        // Simulate before sending
        await simulateTransaction({ transaction: tx, account });
        await sendTx(tx);
      } catch (err: unknown) {
        const message = err instanceof Error ? err.message : "Transaction failed";
        setError(message);
        throw err;
      } finally {
        setIsLoading(false);
      }
    },
    [account, sendTx]
  );

  return { deposit, isLoading, error };
}

export function useVaultWithdraw() {
  const account = useActiveAccount();
  const { mutateAsync: sendTx } = useSendTransaction();
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const withdraw = useCallback(
    async (
      shares: bigint,
      worldIdRoot: bigint,
      nullifierHash: bigint,
      proof: readonly [bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint]
    ) => {
      if (!account) {
        setError("Wallet not connected");
        return;
      }
      setIsLoading(true);
      setError(null);

      try {
        const tx = prepareContractCall({
          contract: vaultContract,
          method:
            "function withdraw(uint256 shares, uint256 worldIdRoot, uint256 nullifierHash, uint256[8] proof)",
          params: [shares, worldIdRoot, nullifierHash, proof],
        });

        await simulateTransaction({ transaction: tx, account });
        await sendTx(tx);
      } catch (err: unknown) {
        const message = err instanceof Error ? err.message : "Transaction failed";
        setError(message);
        throw err;
      } finally {
        setIsLoading(false);
      }
    },
    [account, sendTx]
  );

  return { withdraw, isLoading, error };
}
