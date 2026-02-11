"use client";

import { useReadContract } from "thirdweb/react";
import { getRiskRegistryContract } from "@/lib/contracts";

// Real protocol configuration from deployment
const KNOWN_PROTOCOLS = [
  {
    name: "Aave V3",
    chain: "Sepolia",
    address: "0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951" as const, // Aave V3 Pool Sepolia
  },
];

export function ProtocolBreakdown() {
  const riskRegistry = getRiskRegistryContract();

  // Read risk assessment for Aave V3
  const aaveRiskData = useReadContract({
    contract: riskRegistry,
    method: "function getRiskAssessment(address protocol) view returns (tuple(uint256 score, uint256 lastUpdated, bool isMonitored))",
    params: [KNOWN_PROTOCOLS[0].address],
  });

  const protocols = KNOWN_PROTOCOLS.map((protocol, idx) => {
    const riskData = idx === 0 ? aaveRiskData.data : null;
    const riskScore = riskData ? Number(riskData[0]) : 0;
    const isSafe = riskScore < 5000; // Below 50% risk threshold

    return {
      name: protocol.name,
      chain: protocol.chain,
      supplyRate: null, // Requires external API or Chainlink Data Feed
      allocation: 100, // Currently 100% Aave (read from StrategyRouter in production)
      safe: isSafe,
      riskScore: riskScore / 100, // Convert to percentage
    };
  });

  const isLoading = aaveRiskData.isLoading;
  return (
    <div className="glass-card p-6">
      <h3 className="text-sm text-gray-400 mb-4">Protocol Breakdown</h3>

      {isLoading ? (
        <div className="text-center py-8 text-gray-500">
          Loading protocol data...
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-xs text-gray-500 border-b border-gray-800">
                <th className="text-left py-2">Protocol</th>
                <th className="text-left py-2">Chain</th>
                <th className="text-right py-2">Risk Score</th>
                <th className="text-right py-2">Allocation</th>
                <th className="text-center py-2">Status</th>
              </tr>
            </thead>
            <tbody>
              {protocols.map((p) => (
                <tr
                  key={p.name}
                  className="border-b border-gray-800 last:border-0"
                >
                  <td className="py-3 text-white">{p.name}</td>
                  <td className="py-3 text-gray-400">{p.chain}</td>
                  <td className="py-3 text-right text-white">
                    {p.riskScore.toFixed(2)}%
                  </td>
                  <td className="py-3 text-right text-white">
                    {p.allocation}%
                  </td>
                  <td className="py-3 text-center">
                    <span
                      className={`inline-flex items-center gap-1 text-xs ${p.safe ? "text-aegis-green" : "text-aegis-red"}`}
                    >
                      <span
                        className={`w-1.5 h-1.5 rounded-full ${p.safe ? "bg-aegis-green" : "bg-aegis-red"}`}
                      />
                      {p.safe ? "Safe" : "At Risk"}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
