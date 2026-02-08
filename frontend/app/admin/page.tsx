"use client";

import Link from "next/link";
import { useActiveAccount } from "thirdweb/react";
import { ConnectWallet } from "@/components/ConnectWallet";
import { useVaultRead } from "@/hooks/useVaultContract";
import { useRiskData } from "@/hooks/useRiskData";
import { formatEth, formatBps } from "@/lib/formatters";

export default function AdminPage() {
  const account = useActiveAccount();
  const { owner: ownerResult } = useVaultRead();

  const isOwner =
    account &&
    ownerResult.data &&
    account.address.toLowerCase() === (ownerResult.data as string).toLowerCase();

  return (
    <main className="min-h-screen bg-aegis-dark">
      <header className="border-b border-aegis-border px-6 py-4">
        <div className="max-w-7xl mx-auto flex items-center justify-between">
          <div className="flex items-center gap-8">
            <Link href="/" className="text-xl font-bold text-white">
              AEGIS <span className="text-aegis-accent">Protocol</span>
            </Link>
            <nav className="hidden md:flex items-center gap-6 text-sm text-gray-400">
              <Link href="/" className="hover:text-white transition">
                Dashboard
              </Link>
              <Link href="/monitor" className="hover:text-white transition">
                Monitor
              </Link>
              <Link href="/history" className="hover:text-white transition">
                History
              </Link>
              <Link href="/admin" className="text-white">
                Admin
              </Link>
            </nav>
          </div>
          <ConnectWallet />
        </div>
      </header>

      <div className="max-w-7xl mx-auto px-6 py-8">
        {!account ? (
          <div className="glass-card p-12 text-center">
            <p className="text-gray-400">
              Connect your wallet to access the admin panel.
            </p>
          </div>
        ) : !isOwner ? (
          <div className="glass-card p-12 text-center">
            <p className="text-aegis-red text-lg font-medium mb-2">
              Access Denied
            </p>
            <p className="text-gray-400">
              Only the contract owner can access this panel.
            </p>
            <p className="text-xs text-gray-500 mt-4">
              Connected: {account.address}
              <br />
              Owner: {(ownerResult.data as string) || "Loading..."}
            </p>
          </div>
        ) : (
          <AdminPanel />
        )}
      </div>
    </main>
  );
}

function AdminPanel() {
  const { totalAssets, circuitBreakerActive, isSetupComplete, minDeposit } =
    useVaultRead();
  const { riskThreshold, totalAlerts, circuitBreakerState } = useRiskData();

  return (
    <div className="space-y-6">
      <h2 className="text-lg font-semibold text-white">Admin Panel</h2>
      <p className="text-xs text-gray-500">
        Client-side check is UX only. All operations require on-chain
        onlyOwner.
      </p>

      {/* Vault Status */}
      <div className="glass-card p-6">
        <h3 className="text-sm text-gray-400 mb-4">Vault Status</h3>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
          <div>
            <p className="text-xs text-gray-500">Total Assets</p>
            <p className="text-white font-medium">
              {totalAssets.data != null ? formatEth(BigInt(totalAssets.data.toString())) + " ETH" : "---"}
            </p>
          </div>
          <div>
            <p className="text-xs text-gray-500">Circuit Breaker</p>
            <p
              className={
                circuitBreakerActive.data === true
                  ? "text-aegis-red font-medium"
                  : "text-aegis-green font-medium"
              }
            >
              {circuitBreakerActive.data === true ? "ACTIVE" : "INACTIVE"}
            </p>
          </div>
          <div>
            <p className="text-xs text-gray-500">Setup Complete</p>
            <p className="text-white font-medium">
              {isSetupComplete.data === true ? "Yes" : "No"}
            </p>
          </div>
          <div>
            <p className="text-xs text-gray-500">Min Deposit</p>
            <p className="text-white font-medium">
              {minDeposit.data != null ? formatEth(BigInt(minDeposit.data.toString())) + " ETH" : "---"}
            </p>
          </div>
        </div>
      </div>

      {/* Risk Configuration */}
      <div className="glass-card p-6">
        <h3 className="text-sm text-gray-400 mb-4">Risk Configuration</h3>
        <div className="grid grid-cols-2 md:grid-cols-3 gap-4 text-sm">
          <div>
            <p className="text-xs text-gray-500">Risk Threshold</p>
            <p className="text-white font-medium">
              {riskThreshold != null ? formatBps(riskThreshold as bigint) : "---"}
            </p>
          </div>
          <div>
            <p className="text-xs text-gray-500">Total Alerts</p>
            <p className="text-white font-medium">
              {totalAlerts?.toString() || "0"}
            </p>
          </div>
          <div>
            <p className="text-xs text-gray-500">CB Activations</p>
            <p className="text-white font-medium">
              {circuitBreakerState?.activationCount?.toString() || "0"}
            </p>
          </div>
        </div>
      </div>

      {/* Info notice */}
      <div className="glass-card p-4 border-aegis-yellow/20">
        <p className="text-xs text-gray-400">
          Admin transactions (update thresholds, activate/deactivate circuit
          breaker, set allocations) require on-chain execution through a wallet
          transaction. Use the contract directly via Etherscan or a script.
        </p>
      </div>
    </div>
  );
}
