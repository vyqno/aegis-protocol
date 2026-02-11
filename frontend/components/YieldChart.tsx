"use client";

import { useState } from "react";
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Legend,
} from "recharts";
import { useYieldHistory } from "@/hooks/useYieldHistory";
import { CHART_COLORS } from "@/lib/charts";

const TIME_RANGES = ["1H", "6H", "24H", "7D"] as const;

export function YieldChart() {
  const [timeRange, setTimeRange] =
    useState<(typeof TIME_RANGES)[number]>("24H");
  const { data, isLoading, isEmpty } = useYieldHistory(timeRange);

  const chartData = data.map((d) => ({
    time: new Date(d.timestamp).toLocaleTimeString([], {
      hour: "2-digit",
      minute: "2-digit",
    }),
    vault: Number(d.vaultYield.toFixed(2)),
    aave: Number(d.aaveRate.toFixed(2)),
    morpho: Number(d.morphoRate.toFixed(2)),
  }));

  return (
    <div className="glass-card p-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm text-gray-400">Yield Performance</h3>
        <div className="flex gap-1">
          {TIME_RANGES.map((range) => (
            <button
              key={range}
              onClick={() => setTimeRange(range)}
              className={`px-3 py-1 text-xs rounded ${
                timeRange === range
                  ? "bg-aegis-accent text-white"
                  : "bg-gray-800 text-gray-400 hover:bg-gray-700"
              }`}
            >
              {range}
            </button>
          ))}
        </div>
      </div>

      <div className="h-64">
        {isLoading ? (
          <div className="flex items-center justify-center h-full text-gray-500">
            Loading yield data...
          </div>
        ) : isEmpty ? (
          <div className="flex flex-col items-center justify-center h-full text-center">
            <p className="text-gray-500 mb-2">No yield data available yet</p>
            <p className="text-xs text-gray-600">
              Yield reports will appear after CRE workflows are deployed
            </p>
          </div>
        ) : (
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={chartData}>
            <CartesianGrid strokeDasharray="3 3" stroke={CHART_COLORS.grid} />
            <XAxis
              dataKey="time"
              stroke={CHART_COLORS.text}
              fontSize={10}
              tickLine={false}
            />
            <YAxis
              stroke={CHART_COLORS.text}
              fontSize={10}
              tickLine={false}
              tickFormatter={(v: number) => `${v}%`}
            />
            <Tooltip
              contentStyle={{
                backgroundColor: "#111827",
                border: "1px solid #1f2937",
                borderRadius: "0.5rem",
                fontSize: 12,
              }}
              labelStyle={{ color: "#9ca3af" }}
            />
            <Legend
              wrapperStyle={{ fontSize: 12 }}
              iconType="line"
            />
            <Line
              type="monotone"
              dataKey="vault"
              name="AEGIS Vault"
              stroke={CHART_COLORS.vaultYield}
              strokeWidth={2}
              dot={false}
            />
            <Line
              type="monotone"
              dataKey="aave"
              name="Aave V3"
              stroke={CHART_COLORS.aaveRate}
              strokeWidth={1.5}
              dot={false}
              strokeDasharray="4 2"
            />
            <Line
              type="monotone"
              dataKey="morpho"
              name="Morpho"
              stroke={CHART_COLORS.morphoRate}
              strokeWidth={1.5}
              dot={false}
              strokeDasharray="4 2"
            />
          </LineChart>
        </ResponsiveContainer>
        )}
      </div>
    </div>
  );
}
