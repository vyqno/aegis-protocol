// Chart color configuration for recharts (SVG-based, XSS-safe)
export const CHART_COLORS = {
  vaultYield: "#3b82f6",
  aaveRate: "#22c55e",
  morphoRate: "#a855f7",
  sepolia: "#3b82f6",
  baseSepolia: "#a855f7",
  risk: "#ef4444",
  grid: "#1f2937",
  text: "#9ca3af",
} as const;

export const CHART_STYLE = {
  fontSize: 12,
  fontFamily: "inherit",
} as const;
