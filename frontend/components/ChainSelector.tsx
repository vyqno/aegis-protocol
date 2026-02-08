"use client";

import { useActiveWalletChain, useSwitchActiveWalletChain } from "thirdweb/react";
import { sepolia, baseSepolia, CHAIN_NAMES } from "@/lib/chains";

export function ChainSelector() {
  const activeChain = useActiveWalletChain();
  const switchChain = useSwitchActiveWalletChain();

  const chains = [sepolia, baseSepolia];

  return (
    <div className="glass-card p-4">
      <h3 className="text-sm text-gray-400 mb-3">Network</h3>
      <div className="flex gap-2">
        {chains.map((chain) => {
          const isActive = activeChain?.id === chain.id;
          return (
            <button
              key={chain.id}
              onClick={() => switchChain(chain)}
              className={`px-4 py-2 rounded-lg text-sm transition ${
                isActive
                  ? "bg-aegis-accent text-white"
                  : "bg-gray-800 text-gray-400 hover:bg-gray-700"
              }`}
            >
              {CHAIN_NAMES[chain.id] || `Chain ${chain.id}`}
            </button>
          );
        })}
      </div>
    </div>
  );
}
