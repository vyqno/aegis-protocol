"use client";

import { useContractEvents } from "thirdweb/react";
import { prepareEvent } from "thirdweb";
import { getVaultContract } from "@/lib/contracts";
import { formatEth, shortenAddress, formatTimeAgo } from "@/lib/formatters";

const vaultContract = getVaultContract();

const depositEvent = prepareEvent({
  signature:
    "event Deposited(address indexed user, uint256 assets, uint256 shares)",
});

const withdrawEvent = prepareEvent({
  signature:
    "event Withdrawn(address indexed user, uint256 assets, uint256 shares)",
});

export function TransactionHistory() {
  const deposits = useContractEvents({
    contract: vaultContract,
    events: [depositEvent],
    blockRange: 50000,
  });

  const withdrawals = useContractEvents({
    contract: vaultContract,
    events: [withdrawEvent],
    blockRange: 50000,
  });

  const allTxs = [
    ...(deposits.data || []).map((e) => ({
      type: "Deposit" as const,
      user: (e.args as { user: string }).user,
      assets: (e.args as { assets: bigint }).assets,
      blockNumber: e.blockNumber,
    })),
    ...(withdrawals.data || []).map((e) => ({
      type: "Withdraw" as const,
      user: (e.args as { user: string }).user,
      assets: (e.args as { assets: bigint }).assets,
      blockNumber: e.blockNumber,
    })),
  ].sort((a, b) => Number(b.blockNumber - a.blockNumber));

  return (
    <div className="glass-card p-6">
      <h3 className="text-sm text-gray-400 mb-4">Transaction History</h3>

      {allTxs.length === 0 ? (
        <p className="text-sm text-gray-500 text-center py-8">
          No transactions yet
        </p>
      ) : (
        <div className="space-y-2 max-h-96 overflow-y-auto">
          {allTxs.slice(0, 50).map((tx, i) => (
            <div
              key={i}
              className="flex items-center justify-between py-2 border-b border-gray-800 last:border-0"
            >
              <div className="flex items-center gap-3">
                <div
                  className={`w-2 h-2 rounded-full ${tx.type === "Deposit" ? "bg-aegis-green" : "bg-aegis-red"}`}
                />
                <div>
                  <p className="text-sm text-white">{tx.type}</p>
                  <p className="text-xs text-gray-500">
                    {shortenAddress(tx.user)}
                  </p>
                </div>
              </div>
              <div className="text-right">
                <p className="text-sm text-white">{formatEth(tx.assets)} ETH</p>
                <p className="text-xs text-gray-500">
                  Block #{tx.blockNumber.toString()}
                </p>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
