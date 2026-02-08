"use client";

import {
  PieChart,
  Pie,
  Cell,
  ResponsiveContainer,
  Tooltip,
  Legend,
} from "recharts";
import { CHART_COLORS } from "@/lib/charts";

const ALLOCATION_DATA = [
  { name: "Ethereum Sepolia", value: 60, color: CHART_COLORS.sepolia },
  { name: "Base Sepolia", value: 40, color: CHART_COLORS.baseSepolia },
];

export function AllocationPie() {
  return (
    <div className="glass-card p-6">
      <h3 className="text-sm text-gray-400 mb-4">Cross-Chain Allocation</h3>

      <div className="h-64">
        <ResponsiveContainer width="100%" height="100%">
          <PieChart>
            <Pie
              data={ALLOCATION_DATA}
              cx="50%"
              cy="50%"
              innerRadius={60}
              outerRadius={90}
              paddingAngle={4}
              dataKey="value"
            >
              {ALLOCATION_DATA.map((entry, index) => (
                <Cell key={index} fill={entry.color} />
              ))}
            </Pie>
            <Tooltip
              contentStyle={{
                backgroundColor: "#111827",
                border: "1px solid #1f2937",
                borderRadius: "0.5rem",
                fontSize: 12,
              }}
              formatter={(value: number) => [`${value}%`, "Allocation"]}
            />
            <Legend
              wrapperStyle={{ fontSize: 12 }}
              formatter={(value: string) => (
                <span style={{ color: "#9ca3af" }}>{value}</span>
              )}
            />
          </PieChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}
