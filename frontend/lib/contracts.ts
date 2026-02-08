import { getContract } from "thirdweb";
import { client } from "./thirdweb";
import { sepolia } from "./chains";

// Deployed contract addresses (update after deployment)
export const ADDRESSES = {
  aegisVault: (process.env.NEXT_PUBLIC_AEGIS_VAULT || "0x0000000000000000000000000000000000000000") as `0x${string}`,
  riskRegistry: (process.env.NEXT_PUBLIC_RISK_REGISTRY || "0x0000000000000000000000000000000000000000") as `0x${string}`,
  strategyRouter: (process.env.NEXT_PUBLIC_STRATEGY_ROUTER || "0x0000000000000000000000000000000000000000") as `0x${string}`,
  worldIdGate: (process.env.NEXT_PUBLIC_WORLD_ID_GATE || "0x0000000000000000000000000000000000000000") as `0x${string}`,
} as const;

// ABI fragments for AegisVault
export const AEGIS_VAULT_ABI = [
  // User functions
  {
    type: "function",
    name: "deposit",
    inputs: [
      { name: "worldIdRoot", type: "uint256" },
      { name: "nullifierHash", type: "uint256" },
      { name: "proof", type: "uint256[8]" },
    ],
    outputs: [],
    stateMutability: "payable",
  },
  {
    type: "function",
    name: "withdraw",
    inputs: [
      { name: "shares", type: "uint256" },
      { name: "worldIdRoot", type: "uint256" },
      { name: "nullifierHash", type: "uint256" },
      { name: "proof", type: "uint256[8]" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  // View functions
  {
    type: "function",
    name: "getPosition",
    inputs: [{ name: "user", type: "address" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "shares", type: "uint256" },
          { name: "depositTimestamp", type: "uint256" },
          { name: "depositAmount", type: "uint256" },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getTotalAssets",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "isCircuitBreakerActive",
    inputs: [],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "convertToAssets",
    inputs: [{ name: "shares", type: "uint256" }],
    outputs: [{ name: "assets", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "convertToShares",
    inputs: [{ name: "assets", type: "uint256" }],
    outputs: [{ name: "shares", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "totalShares",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "minDeposit",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "isSetupComplete",
    inputs: [],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "owner",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
  },
  // Events
  {
    type: "event",
    name: "Deposited",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "assets", type: "uint256", indexed: false },
      { name: "shares", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "Withdrawn",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "assets", type: "uint256", indexed: false },
      { name: "shares", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "CircuitBreakerActivated",
    inputs: [
      { name: "timestamp", type: "uint256", indexed: false },
      { name: "reportId", type: "bytes32", indexed: true },
    ],
  },
  {
    type: "event",
    name: "CircuitBreakerDeactivated",
    inputs: [
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "YieldReportReceived",
    inputs: [
      { name: "reportKey", type: "bytes32", indexed: true },
      { name: "data", type: "bytes", indexed: false },
    ],
  },
  {
    type: "event",
    name: "RiskReportReceived",
    inputs: [
      { name: "reportKey", type: "bytes32", indexed: true },
      { name: "shouldActivate", type: "bool", indexed: false },
      { name: "riskScore", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "VaultOperationReceived",
    inputs: [
      { name: "reportKey", type: "bytes32", indexed: true },
      { name: "data", type: "bytes", indexed: false },
    ],
  },
] as const;

// ABI fragments for RiskRegistry
export const RISK_REGISTRY_ABI = [
  {
    type: "function",
    name: "getRiskAssessment",
    inputs: [{ name: "protocol", type: "address" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "score", type: "uint256" },
          { name: "lastUpdated", type: "uint256" },
          { name: "isMonitored", type: "bool" },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getCircuitBreakerState",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "isActive", type: "bool" },
          { name: "activatedAt", type: "uint256" },
          { name: "activationCount", type: "uint256" },
          { name: "windowStart", type: "uint256" },
          { name: "lastTriggerReportId", type: "bytes32" },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "isCircuitBreakerActive",
    inputs: [],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "riskThreshold",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "totalAlerts",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "isProtocolSafe",
    inputs: [{ name: "protocol", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
  // Events
  {
    type: "event",
    name: "RiskScoreUpdated",
    inputs: [
      { name: "protocol", type: "address", indexed: true },
      { name: "oldScore", type: "uint256", indexed: false },
      { name: "newScore", type: "uint256", indexed: false },
      { name: "reportId", type: "bytes32", indexed: true },
    ],
  },
  {
    type: "event",
    name: "RiskAlertCreated",
    inputs: [
      { name: "protocol", type: "address", indexed: true },
      { name: "score", type: "uint256", indexed: false },
      { name: "threshold", type: "uint256", indexed: false },
      { name: "alertNumber", type: "uint256", indexed: false },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "CircuitBreakerActivated",
    inputs: [
      { name: "trigger", type: "address", indexed: true },
      { name: "reportId", type: "bytes32", indexed: true },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "CircuitBreakerDeactivated",
    inputs: [
      { name: "deactivator", type: "address", indexed: true },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
] as const;

// ABI fragments for StrategyRouter
export const STRATEGY_ROUTER_ABI = [
  {
    type: "function",
    name: "getRemainingTransferBudget",
    inputs: [],
    outputs: [{ name: "remaining", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getTargetAllocation",
    inputs: [{ name: "chainSelector", type: "uint64" }],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "isChainAllowed",
    inputs: [{ name: "chainSelector", type: "uint64" }],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
  {
    type: "event",
    name: "StrategyExecuted",
    inputs: [
      { name: "reportId", type: "bytes32", indexed: true },
      { name: "targetProtocol", type: "address", indexed: true },
      { name: "actionType", type: "bytes1", indexed: false },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "CrossChainMessageSent",
    inputs: [
      { name: "ccipMessageId", type: "bytes32", indexed: true },
      { name: "destinationChainSelector", type: "uint64", indexed: true },
      { name: "receiver", type: "address", indexed: false },
      { name: "amount", type: "uint256", indexed: false },
      { name: "nonce", type: "uint256", indexed: false },
    ],
  },
] as const;

// Contract instances (no typed ABI — use human-readable method signatures with useReadContract)
export function getVaultContract(chain = sepolia) {
  return getContract({
    client,
    chain,
    address: ADDRESSES.aegisVault,
  });
}

export function getRiskRegistryContract(chain = sepolia) {
  return getContract({
    client,
    chain,
    address: ADDRESSES.riskRegistry,
  });
}

export function getStrategyRouterContract(chain = sepolia) {
  return getContract({
    client,
    chain,
    address: ADDRESSES.strategyRouter,
  });
}
