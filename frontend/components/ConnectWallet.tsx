"use client";

import { ConnectButton } from "thirdweb/react";
import { client } from "@/lib/thirdweb";
import { sepolia, baseSepolia } from "@/lib/chains";

export function ConnectWallet() {
  return (
    <ConnectButton
      client={client}
      chains={[sepolia, baseSepolia]}
      theme="dark"
      connectButton={{
        label: "Connect Wallet",
        style: {
          backgroundColor: "#3b82f6",
          borderRadius: "0.5rem",
          fontSize: "0.875rem",
        },
      }}
    />
  );
}
