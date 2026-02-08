"use client";

// Mock protocol data (replace with real on-chain reads after deployment)
const PROTOCOLS = [
  {
    name: "Aave V3",
    chain: "Sepolia",
    supplyRate: 3.85,
    allocation: 60,
    safe: true,
  },
  {
    name: "Morpho",
    chain: "Base Sepolia",
    supplyRate: 4.22,
    allocation: 40,
    safe: true,
  },
];

export function ProtocolBreakdown() {
  return (
    <div className="glass-card p-6">
      <h3 className="text-sm text-gray-400 mb-4">Protocol Breakdown</h3>

      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-xs text-gray-500 border-b border-gray-800">
              <th className="text-left py-2">Protocol</th>
              <th className="text-left py-2">Chain</th>
              <th className="text-right py-2">Supply Rate</th>
              <th className="text-right py-2">Allocation</th>
              <th className="text-center py-2">Status</th>
            </tr>
          </thead>
          <tbody>
            {PROTOCOLS.map((p) => (
              <tr
                key={p.name}
                className="border-b border-gray-800 last:border-0"
              >
                <td className="py-3 text-white">{p.name}</td>
                <td className="py-3 text-gray-400">{p.chain}</td>
                <td className="py-3 text-right text-white">
                  {p.supplyRate.toFixed(2)}%
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
    </div>
  );
}
