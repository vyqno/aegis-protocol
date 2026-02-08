"use client";

import { formatEther } from "viem";
import { useVaultPosition } from "@/hooks/useVaultPosition";

export function PositionCard() {
  const { position, currentValue, isLoading } = useVaultPosition();

  if (isLoading) {
    return (
      <div className="glass-card p-6 animate-pulse">
        <div className="h-4 bg-gray-700 rounded w-1/3 mb-4" />
        <div className="h-8 bg-gray-700 rounded w-1/2" />
      </div>
    );
  }

  const deposited = position?.depositAmount || 0n;
  const shares = position?.shares || 0n;
  const value = currentValue || 0n;
  const depositedEth = formatEther(deposited);
  const valueEth = formatEther(value);

  const pnl =
    deposited > 0n ? ((value - deposited) * 10000n) / deposited : 0n;
  const pnlPercent = Number(pnl) / 100;
  const isPositive = pnl >= 0n;

  return (
    <div className="glass-card p-6">
      <h3 className="text-sm text-gray-400 mb-4">Your Position</h3>
      <div className="grid grid-cols-2 gap-4">
        <div>
          <p className="text-xs text-gray-500 mb-1">Deposited</p>
          <p className="text-2xl font-bold text-white">
            {Number(depositedEth).toFixed(4)} ETH
          </p>
        </div>
        <div>
          <p className="text-xs text-gray-500 mb-1">Current Value</p>
          <p className="text-2xl font-bold text-white">
            {Number(valueEth).toFixed(4)} ETH
            {deposited > 0n && (
              <span
                className={`text-sm ml-2 ${isPositive ? "text-aegis-green" : "text-aegis-red"}`}
              >
                ({isPositive ? "+" : ""}
                {pnlPercent.toFixed(2)}%)
              </span>
            )}
          </p>
        </div>
      </div>
      {shares > 0n && (
        <p className="text-xs text-gray-500 mt-3">
          Shares: {formatEther(shares)}
          {position?.depositTimestamp
            ? ` | Deposited: ${new Date(Number(position.depositTimestamp) * 1000).toLocaleDateString()}`
            : ""}
        </p>
      )}
    </div>
  );
}
