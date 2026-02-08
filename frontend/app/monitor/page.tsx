"use client";

import Link from "next/link";
import { ConnectWallet } from "@/components/ConnectWallet";
import { RiskMonitor } from "@/components/RiskMonitor";
import { YieldChart } from "@/components/YieldChart";
import { AllocationPie } from "@/components/AllocationPie";
import { WorkflowStatus } from "@/components/WorkflowStatus";
import { ProtocolBreakdown } from "@/components/ProtocolBreakdown";
import { AlertFeed } from "@/components/AlertFeed";

export default function MonitorPage() {
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
              <Link href="/monitor" className="text-white">
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

      <div className="max-w-7xl mx-auto px-6 py-8 space-y-6">
        <h2 className="text-lg font-semibold text-white">Risk Monitoring</h2>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <RiskMonitor />
          <WorkflowStatus />
        </div>

        <YieldChart />

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <AllocationPie />
          <AlertFeed />
        </div>

        <ProtocolBreakdown />
      </div>
    </main>
  );
}
