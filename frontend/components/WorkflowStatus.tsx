"use client";

import { useWorkflowEvents } from "@/hooks/useWorkflowEvents";

interface WorkflowInfo {
  name: string;
  trigger: string;
  color: string;
}

const WORKFLOWS: WorkflowInfo[] = [
  { name: "Yield Scanner", trigger: "Cron (5 min)", color: "bg-aegis-accent" },
  { name: "Risk Sentinel", trigger: "Log Trigger", color: "bg-aegis-red" },
  { name: "Vault Manager", trigger: "HTTP", color: "bg-aegis-green" },
];

export function WorkflowStatus() {
  const { yieldEvents, riskEvents, vaultOpEvents, isLoading } =
    useWorkflowEvents();

  const eventCounts = [
    yieldEvents.length,
    riskEvents.length,
    vaultOpEvents.length,
  ];

  return (
    <div className="glass-card p-6">
      <h3 className="text-sm text-gray-400 mb-4">CRE Workflow Status</h3>

      <div className="space-y-3">
        {WORKFLOWS.map((wf, i) => (
          <div
            key={wf.name}
            className="flex items-center justify-between py-2 border-b border-gray-800 last:border-0"
          >
            <div className="flex items-center gap-3">
              <div className={`w-2 h-2 rounded-full ${wf.color}`} />
              <div>
                <p className="text-sm text-white">{wf.name}</p>
                <p className="text-xs text-gray-500">{wf.trigger}</p>
              </div>
            </div>
            <div className="text-right">
              <p className="text-sm text-white">
                {isLoading ? "..." : eventCounts[i]} events
              </p>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
