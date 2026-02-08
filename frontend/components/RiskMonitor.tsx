"use client";

import { useRiskData } from "@/hooks/useRiskData";
import { formatBps, formatTimeAgo } from "@/lib/formatters";

export function RiskMonitor() {
  const { circuitBreakerState, riskThreshold, totalAlerts, isLoading } =
    useRiskData();

  if (isLoading) {
    return (
      <div className="glass-card p-6 animate-pulse">
        <div className="h-4 bg-gray-700 rounded w-1/3 mb-4" />
        <div className="h-20 bg-gray-700 rounded" />
      </div>
    );
  }

  const cbActive = circuitBreakerState?.isActive || false;
  const activatedAt = circuitBreakerState?.activatedAt || 0n;
  const activationCount = circuitBreakerState?.activationCount || 0n;
  const threshold = riskThreshold || 7000n;
  const alerts = totalAlerts || 0n;

  // Health factor: inverse of risk (higher = safer)
  // When threshold is 7000 bps and no CB active, health is good
  const healthFactor = cbActive ? 0.5 : 1.85;
  const healthBarWidth = Math.min(healthFactor / 2.5, 1) * 100;

  // Mock risk score (in production, read from protocol assessment)
  const riskScore = cbActive ? 8500 : 3200;
  const riskBarWidth = (riskScore / 10000) * 100;

  return (
    <div className="glass-card p-6">
      <h3 className="text-sm text-gray-400 mb-4">Risk Monitor</h3>

      <div className="space-y-4">
        {/* Health Factor */}
        <div>
          <div className="flex justify-between text-xs text-gray-400 mb-1">
            <span>Health Factor</span>
            <span className={healthFactor >= 1.5 ? "text-aegis-green" : "text-aegis-red"}>
              {healthFactor.toFixed(2)}
            </span>
          </div>
          <div className="w-full bg-gray-800 rounded-full h-2">
            <div
              className={`h-2 rounded-full transition-all ${healthFactor >= 1.5 ? "bg-aegis-green" : "bg-aegis-red"}`}
              style={{ width: `${healthBarWidth}%` }}
            />
          </div>
        </div>

        {/* Risk Score */}
        <div>
          <div className="flex justify-between text-xs text-gray-400 mb-1">
            <span>Risk Score</span>
            <span>{riskScore} / 10000</span>
          </div>
          <div className="w-full bg-gray-800 rounded-full h-2">
            <div
              className={`h-2 rounded-full transition-all ${riskScore > Number(threshold) ? "bg-aegis-red" : "bg-aegis-accent"}`}
              style={{ width: `${riskBarWidth}%` }}
            />
          </div>
        </div>

        {/* Circuit Breaker */}
        <div className="flex items-center justify-between py-2 border-t border-gray-800">
          <div className="flex items-center gap-2">
            <div
              className={`w-2.5 h-2.5 rounded-full ${cbActive ? "bg-aegis-red animate-pulse" : "bg-aegis-green"}`}
            />
            <span className="text-sm text-gray-300">Circuit Breaker</span>
          </div>
          <span
            className={`text-sm font-medium ${cbActive ? "text-aegis-red" : "text-aegis-green"}`}
          >
            {cbActive ? "ACTIVE" : "INACTIVE"}
          </span>
        </div>

        {/* Stats */}
        <div className="grid grid-cols-3 gap-4 pt-2 border-t border-gray-800 text-center">
          <div>
            <p className="text-xs text-gray-500">Threshold</p>
            <p className="text-sm text-white font-medium">
              {formatBps(threshold)}
            </p>
          </div>
          <div>
            <p className="text-xs text-gray-500">Alerts (Total)</p>
            <p className="text-sm text-white font-medium">{alerts.toString()}</p>
          </div>
          <div>
            <p className="text-xs text-gray-500">CB Activations</p>
            <p className="text-sm text-white font-medium">
              {activationCount.toString()}
            </p>
          </div>
        </div>

        {cbActive && activatedAt > 0n && (
          <p className="text-xs text-gray-500">
            Activated: {formatTimeAgo(activatedAt)}
          </p>
        )}
      </div>
    </div>
  );
}
