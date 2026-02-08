"use client";

import { useAlerts } from "@/hooks/useAlerts";
import { formatBps, shortenAddress } from "@/lib/formatters";

export function AlertFeed() {
  const { riskAlerts, cbActivations, cbDeactivations, isLoading } =
    useAlerts();

  if (isLoading) {
    return (
      <div className="glass-card p-6 animate-pulse">
        <div className="h-4 bg-gray-700 rounded w-1/3 mb-4" />
        <div className="h-32 bg-gray-700 rounded" />
      </div>
    );
  }

  const hasAlerts =
    riskAlerts.length > 0 ||
    cbActivations.length > 0 ||
    cbDeactivations.length > 0;

  return (
    <div className="glass-card p-6">
      <h3 className="text-sm text-gray-400 mb-4">
        Alert Feed
        {riskAlerts.length > 0 && (
          <span className="ml-2 text-xs bg-aegis-red/20 text-aegis-red px-2 py-0.5 rounded-full">
            {riskAlerts.length}
          </span>
        )}
      </h3>

      {!hasAlerts ? (
        <p className="text-sm text-gray-500 text-center py-8">
          No alerts - all systems nominal
        </p>
      ) : (
        <div className="space-y-2 max-h-64 overflow-y-auto">
          {cbActivations.map((evt, i) => (
            <div
              key={`cb-on-${i}`}
              className="flex items-center gap-3 py-2 border-b border-gray-800"
            >
              <div className="w-2 h-2 rounded-full bg-aegis-red" />
              <div>
                <p className="text-sm text-aegis-red">
                  Circuit Breaker Activated
                </p>
                <p className="text-xs text-gray-500">
                  Trigger: {shortenAddress((evt.args as { trigger: string }).trigger)}
                </p>
              </div>
            </div>
          ))}

          {cbDeactivations.map((evt, i) => (
            <div
              key={`cb-off-${i}`}
              className="flex items-center gap-3 py-2 border-b border-gray-800"
            >
              <div className="w-2 h-2 rounded-full bg-aegis-green" />
              <div>
                <p className="text-sm text-aegis-green">
                  Circuit Breaker Deactivated
                </p>
                <p className="text-xs text-gray-500">
                  By: {shortenAddress((evt.args as { deactivator: string }).deactivator)}
                </p>
              </div>
            </div>
          ))}

          {riskAlerts.map((evt, i) => {
            const args = evt.args as {
              protocol: string;
              score: bigint;
              threshold: bigint;
            };
            return (
              <div
                key={`alert-${i}`}
                className="flex items-center gap-3 py-2 border-b border-gray-800 last:border-0"
              >
                <div className="w-2 h-2 rounded-full bg-aegis-yellow" />
                <div>
                  <p className="text-sm text-aegis-yellow">Risk Alert</p>
                  <p className="text-xs text-gray-500">
                    {shortenAddress(args.protocol)} | Score:{" "}
                    {formatBps(args.score)} | Threshold:{" "}
                    {formatBps(args.threshold)}
                  </p>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
