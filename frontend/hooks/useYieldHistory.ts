"use client";

import { useState, useEffect } from "react";

// Mock yield history data for demo (replaced by real event indexing after deployment)
export interface YieldDataPoint {
  timestamp: number;
  vaultYield: number;
  aaveRate: number;
  morphoRate: number;
}

function generateMockData(hours: number): YieldDataPoint[] {
  const points: YieldDataPoint[] = [];
  const now = Date.now();
  const interval = (hours * 3600 * 1000) / 50; // 50 data points

  for (let i = 50; i >= 0; i--) {
    const ts = now - i * interval;
    const baseYield = 4.5 + Math.sin(i * 0.2) * 0.5;
    points.push({
      timestamp: ts,
      vaultYield: baseYield + Math.random() * 0.3,
      aaveRate: 3.8 + Math.sin(i * 0.15) * 0.4 + Math.random() * 0.2,
      morphoRate: 4.2 + Math.cos(i * 0.18) * 0.3 + Math.random() * 0.2,
    });
  }
  return points;
}

export function useYieldHistory(timeRange: "1H" | "6H" | "24H" | "7D" = "24H") {
  const [data, setData] = useState<YieldDataPoint[]>([]);

  useEffect(() => {
    const hours =
      timeRange === "1H" ? 1 : timeRange === "6H" ? 6 : timeRange === "24H" ? 24 : 168;
    setData(generateMockData(hours));
  }, [timeRange]);

  return { data };
}
