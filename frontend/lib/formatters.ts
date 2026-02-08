import { formatEther as viemFormatEther } from "viem";

export function formatEth(wei: bigint, decimals = 4): string {
  return Number(viemFormatEther(wei)).toFixed(decimals);
}

export function formatBps(bps: bigint | number): string {
  const value = typeof bps === "bigint" ? Number(bps) : bps;
  return (value / 100).toFixed(2) + "%";
}

export function formatTimestamp(ts: bigint | number): string {
  const value = typeof ts === "bigint" ? Number(ts) : ts;
  if (value === 0) return "Never";
  const date = new Date(value * 1000);
  return date.toLocaleString();
}

export function formatTimeAgo(ts: bigint | number): string {
  const value = typeof ts === "bigint" ? Number(ts) : ts;
  if (value === 0) return "Never";
  const seconds = Math.floor(Date.now() / 1000 - value);
  if (seconds < 60) return `${seconds}s ago`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
  return `${Math.floor(seconds / 86400)}d ago`;
}

export function shortenAddress(addr: string): string {
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

export function shortenHash(hash: string): string {
  return `${hash.slice(0, 10)}...${hash.slice(-6)}`;
}
