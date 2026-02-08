import { defineChain } from "thirdweb";

export const sepolia = defineChain(11155111);
export const baseSepolia = defineChain(84532);

export const SUPPORTED_CHAINS = [sepolia, baseSepolia] as const;

export const CHAIN_NAMES: Record<number, string> = {
  11155111: "Ethereum Sepolia",
  84532: "Base Sepolia",
};

export const CCIP_SELECTORS: Record<number, string> = {
  11155111: "16015286601757825753",
  84532: "10344971235874465080",
};
