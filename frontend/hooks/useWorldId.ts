"use client";

import { useState, useCallback } from "react";

const PROOF_MAX_AGE_MS = 45 * 60 * 1000; // 45 minutes

export interface WorldIdProof {
  merkle_root: string;
  nullifier_hash: string;
  proof: string;
  timestamp: number;
}

// Mock proof for testnet (World ID simulator)
const MOCK_PROOF: WorldIdProof = {
  merkle_root: "1",
  nullifier_hash: "1",
  proof:
    "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
  timestamp: Date.now(),
};

export function useWorldId() {
  const [proof, setProof] = useState<WorldIdProof | null>(null);
  const [isVerifying, setIsVerifying] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const verify = useCallback(async () => {
    setIsVerifying(true);
    setError(null);

    try {
      // For testnet: use mock proof (World ID simulator)
      // In production, this would open the IDKitWidget
      const mockProof = { ...MOCK_PROOF, timestamp: Date.now() };
      setProof(mockProof);
      return mockProof;
    } catch (err: unknown) {
      const message =
        err instanceof Error ? err.message : "Verification failed";
      setError(message);
      return null;
    } finally {
      setIsVerifying(false);
    }
  }, []);

  const isProofFresh = useCallback(() => {
    if (!proof) return false;
    return Date.now() - proof.timestamp < PROOF_MAX_AGE_MS;
  }, [proof]);

  // Convert proof to contract-compatible format
  const getContractProof = useCallback((): {
    root: bigint;
    nullifierHash: bigint;
    proof: readonly [bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint];
  } | null => {
    if (!proof) return null;
    return {
      root: BigInt(proof.merkle_root),
      nullifierHash: BigInt(proof.nullifier_hash),
      proof: [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n] as const,
    };
  }, [proof]);

  return {
    proof,
    isVerifying,
    error,
    verify,
    isProofFresh,
    getContractProof,
  };
}
