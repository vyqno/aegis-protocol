"use client";

import { useActiveAccount } from "thirdweb/react";
import { ConnectWallet } from "@/components/ConnectWallet";
import { VaultDashboard } from "@/components/VaultDashboard";
import Link from "next/link";

export default function Home() {
  const account = useActiveAccount();

  return (
    <main className="min-h-screen bg-aegis-dark">
      {/* Header */}
      <header className="border-b border-aegis-border px-6 py-4">
        <div className="max-w-7xl mx-auto flex items-center justify-between">
          <div className="flex items-center gap-8">
            <h1 className="text-xl font-bold text-white">
              AEGIS <span className="text-aegis-accent">Protocol</span>
            </h1>
            <nav className="hidden md:flex items-center gap-6 text-sm text-gray-400">
              <Link href="/" className="text-white">
                Dashboard
              </Link>
              <Link href="/monitor" className="hover:text-white transition">
                Monitor
              </Link>
              <Link href="/history" className="hover:text-white transition">
                History
              </Link>
              <Link href="/admin" className="hover:text-white transition">
                Admin
              </Link>
            </nav>
          </div>
          <ConnectWallet />
        </div>
      </header>

      {/* Main content */}
      <div className="max-w-7xl mx-auto px-6 py-8">
        {account ? (
          <VaultDashboard />
        ) : (
          <div className="flex flex-col items-center justify-center min-h-[60vh] text-center">
            <div className="glass-card p-12 max-w-lg">
              <h2 className="text-3xl font-bold text-white mb-4">
                AI-Powered DeFi Guardian
              </h2>
              <p className="text-gray-400 mb-8">
                Autonomous yield optimization, real-time risk monitoring, and
                sybil-resistant access powered by Chainlink CRE, AI, and World
                ID.
              </p>
              <ConnectWallet />
            </div>
          </div>
        )}
      </div>
    </main>
  );
}
