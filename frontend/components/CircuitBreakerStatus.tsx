"use client";

import { useVaultRead } from "@/hooks/useVaultContract";

export function CircuitBreakerStatus() {
  const { circuitBreakerActive } = useVaultRead();

  const isActive = circuitBreakerActive.data === true;

  return (
    <div className="glass-card p-4 flex items-center justify-between">
      <div className="flex items-center gap-3">
        <div
          className={`w-3 h-3 rounded-full ${isActive ? "bg-aegis-red animate-pulse" : "bg-aegis-green"}`}
        />
        <span className="text-sm text-gray-300">Circuit Breaker</span>
      </div>
      <span
        className={`text-sm font-medium ${isActive ? "text-aegis-red" : "text-aegis-green"}`}
      >
        {isActive ? "ACTIVE" : "INACTIVE"}
      </span>
    </div>
  );
}
