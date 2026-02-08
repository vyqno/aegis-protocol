"use client";

import { formatEther } from "viem";
import { useVaultRead } from "@/hooks/useVaultContract";
import { PositionCard } from "./PositionCard";
import { DepositForm } from "./DepositForm";
import { WithdrawForm } from "./WithdrawForm";
import { CircuitBreakerStatus } from "./CircuitBreakerStatus";
import { ChainSelector } from "./ChainSelector";

export function VaultDashboard() {
  const { totalAssets, totalShares } = useVaultRead();

  return (
    <div className="space-y-6">
      {/* Top stats */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div className="glass-card p-6">
          <p className="text-xs text-gray-500 mb-1">Total Vault Assets</p>
          <p className="text-2xl font-bold text-white">
            {totalAssets.data
              ? `${Number(formatEther(totalAssets.data)).toFixed(4)} ETH`
              : "---"}
          </p>
        </div>
        <div className="glass-card p-6">
          <p className="text-xs text-gray-500 mb-1">Total Shares</p>
          <p className="text-2xl font-bold text-white">
            {totalShares.data
              ? Number(formatEther(totalShares.data)).toFixed(4)
              : "---"}
          </p>
        </div>
        <CircuitBreakerStatus />
      </div>

      {/* User position */}
      <PositionCard />

      {/* Deposit / Withdraw side by side */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <DepositForm />
        <WithdrawForm />
      </div>

      {/* Chain selector */}
      <ChainSelector />

      {/* Chain allocations placeholder */}
      <div className="glass-card p-6">
        <h3 className="text-sm text-gray-400 mb-4">Chain Allocations</h3>
        <div className="space-y-3">
          <AllocationBar label="Sepolia" percentage={60} color="bg-aegis-accent" />
          <AllocationBar label="Base Sepolia" percentage={40} color="bg-purple-500" />
        </div>
      </div>
    </div>
  );
}

function AllocationBar({
  label,
  percentage,
  color,
}: {
  label: string;
  percentage: number;
  color: string;
}) {
  return (
    <div>
      <div className="flex justify-between text-xs text-gray-400 mb-1">
        <span>{label}</span>
        <span>{percentage}%</span>
      </div>
      <div className="w-full bg-gray-800 rounded-full h-2">
        <div
          className={`${color} h-2 rounded-full transition-all`}
          style={{ width: `${percentage}%` }}
        />
      </div>
    </div>
  );
}
