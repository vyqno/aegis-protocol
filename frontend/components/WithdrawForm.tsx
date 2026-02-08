"use client";

import { useState } from "react";
import { parseEther } from "viem";
import { useActiveWalletChain } from "thirdweb/react";
import { useVaultWithdraw, useVaultRead } from "@/hooks/useVaultContract";
import { useVaultPosition } from "@/hooks/useVaultPosition";
import { useWorldId } from "@/hooks/useWorldId";
import { sepolia, baseSepolia } from "@/lib/chains";

const VALID_CHAINS = [sepolia.id, baseSepolia.id];

export function WithdrawForm() {
  const [shares, setShares] = useState("");
  const activeChain = useActiveWalletChain();
  const { withdraw, isLoading, error: txError } = useVaultWithdraw();
  const { circuitBreakerActive } = useVaultRead();
  const { position } = useVaultPosition();
  const {
    proof,
    verify,
    isVerifying,
    isProofFresh,
    getContractProof,
    error: idError,
  } = useWorldId();

  const isCBActive = circuitBreakerActive.data === true;
  const isWrongChain = activeChain && !VALID_CHAINS.includes(activeChain.id);
  const userShares = position?.shares || 0n;

  const handleWithdraw = async () => {
    if (!shares || isCBActive || isWrongChain) return;

    let currentProof = getContractProof();
    if (!currentProof || !isProofFresh()) {
      const newProof = await verify();
      if (!newProof) return;
      currentProof = {
        root: BigInt(newProof.merkle_root),
        nullifierHash: BigInt(newProof.nullifier_hash),
        proof: [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n] as const,
      };
    }

    const sharesBigint = parseEther(shares);
    await withdraw(
      sharesBigint,
      currentProof.root,
      currentProof.nullifierHash,
      currentProof.proof
    );
    setShares("");
  };

  const handleMax = () => {
    if (userShares > 0n) {
      setShares((Number(userShares) / 1e18).toString());
    }
  };

  return (
    <div className="glass-card p-6">
      <h3 className="text-sm text-gray-400 mb-4">Withdraw</h3>

      <div className="space-y-4">
        <div className="relative">
          <input
            type="text"
            inputMode="decimal"
            placeholder="Shares to withdraw"
            value={shares}
            onChange={(e) => setShares(e.target.value)}
            className="w-full bg-gray-800 border border-gray-700 rounded-lg px-4 py-3 text-white placeholder-gray-500 focus:outline-none focus:border-aegis-accent pr-16"
          />
          <button
            onClick={handleMax}
            className="absolute right-3 top-1/2 -translate-y-1/2 text-xs text-aegis-accent hover:underline"
          >
            MAX
          </button>
        </div>

        {/* World ID status */}
        <div className="flex items-center gap-2 text-xs">
          <div
            className={`w-2 h-2 rounded-full ${proof && isProofFresh() ? "bg-aegis-green" : "bg-gray-500"}`}
          />
          <span className="text-gray-400">
            {proof && isProofFresh()
              ? "World ID verified"
              : "World ID verification required"}
          </span>
          {(!proof || !isProofFresh()) && (
            <button
              onClick={verify}
              disabled={isVerifying}
              className="text-aegis-accent hover:underline ml-auto"
            >
              {isVerifying ? "Verifying..." : "Verify"}
            </button>
          )}
        </div>

        {isCBActive && (
          <p className="text-aegis-red text-xs">
            Circuit breaker is active. Withdrawals are paused.
          </p>
        )}

        {isWrongChain && (
          <p className="text-aegis-yellow text-xs">
            Please switch to Sepolia or Base Sepolia.
          </p>
        )}

        <button
          onClick={handleWithdraw}
          disabled={
            isLoading || !shares || isCBActive || !!isWrongChain
          }
          className="w-full bg-gray-700 hover:bg-gray-600 disabled:bg-gray-800 disabled:text-gray-500 text-white py-3 rounded-lg font-medium transition"
        >
          {isLoading ? "Withdrawing..." : "Withdraw"}
        </button>

        {(txError || idError) && (
          <p className="text-aegis-red text-xs break-all">
            {txError || idError}
          </p>
        )}
      </div>
    </div>
  );
}
