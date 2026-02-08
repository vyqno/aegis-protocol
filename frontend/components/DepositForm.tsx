"use client";

import { useState } from "react";
import { useActiveWalletChain } from "thirdweb/react";
import { useVaultDeposit, useVaultRead } from "@/hooks/useVaultContract";
import { useWorldId } from "@/hooks/useWorldId";
import { sepolia, baseSepolia } from "@/lib/chains";

const VALID_CHAINS = [sepolia.id, baseSepolia.id];

function validateAmount(value: string): string | null {
  if (!/^\d+\.?\d*$/.test(value)) return "Invalid number";
  const parsed = parseFloat(value);
  if (parsed <= 0) return "Amount must be positive";
  if (parsed > 1000) return "Exceeds maximum deposit";
  return null;
}

export function DepositForm() {
  const [amount, setAmount] = useState("");
  const activeChain = useActiveWalletChain();
  const { deposit, isLoading, error: txError } = useVaultDeposit();
  const { circuitBreakerActive } = useVaultRead();
  const {
    proof,
    verify,
    isVerifying,
    isProofFresh,
    getContractProof,
    error: idError,
  } = useWorldId();

  const validationError = amount ? validateAmount(amount) : null;
  const isCBActive = circuitBreakerActive.data === true;
  const isWrongChain = activeChain && !VALID_CHAINS.includes(activeChain.id);

  const handleDeposit = async () => {
    if (validationError || isCBActive || isWrongChain) return;

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

    await deposit(
      amount,
      currentProof.root,
      currentProof.nullifierHash,
      currentProof.proof
    );
    setAmount("");
  };

  return (
    <div className="glass-card p-6">
      <h3 className="text-sm text-gray-400 mb-4">Deposit</h3>

      <div className="space-y-4">
        <div>
          <input
            type="text"
            inputMode="decimal"
            placeholder="Amount in ETH"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            className="w-full bg-gray-800 border border-gray-700 rounded-lg px-4 py-3 text-white placeholder-gray-500 focus:outline-none focus:border-aegis-accent"
          />
          {validationError && (
            <p className="text-aegis-red text-xs mt-1">{validationError}</p>
          )}
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
            Circuit breaker is active. Deposits are paused.
          </p>
        )}

        {isWrongChain && (
          <p className="text-aegis-yellow text-xs">
            Please switch to Sepolia or Base Sepolia.
          </p>
        )}

        <button
          onClick={handleDeposit}
          disabled={
            isLoading ||
            !amount ||
            !!validationError ||
            isCBActive ||
            !!isWrongChain
          }
          className="w-full bg-aegis-accent hover:bg-blue-600 disabled:bg-gray-700 disabled:text-gray-500 text-white py-3 rounded-lg font-medium transition"
        >
          {isLoading ? "Depositing..." : "Deposit"}
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
