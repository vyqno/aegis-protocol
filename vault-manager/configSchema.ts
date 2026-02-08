// AEGIS Protocol - Vault Manager Config Schema
// Zod validation for CRE workflow configuration (MEDIUM-003)

import { z } from "zod";

/// @notice Zod schema for EVM chain configuration
const evmConfigSchema = z.object({
  vaultAddress: z
    .string()
    .startsWith("0x")
    .length(42, "EVM address must be 42 characters"),
  worldIdGateAddress: z
    .string()
    .startsWith("0x")
    .length(42, "EVM address must be 42 characters"),
  chainSelectorName: z.string().min(1, "Chain selector name required"),
  gasLimit: z.string().regex(/^\d+$/, "Gas limit must be numeric string"),
});

/// @notice Zod schema for World ID configuration
const worldIdSchema = z.object({
  appId: z.string().min(1, "World ID app ID required"),
  actionId: z.string().min(1, "World ID action ID required"),
});

/// @notice Zod schema for the full vault-manager config
export const configSchema = z.object({
  evms: z
    .array(evmConfigSchema)
    .min(1, "At least one EVM chain required"),
  worldId: worldIdSchema,
  authorizedPublicKey: z.string().optional(),
});

/// @notice Inferred TypeScript type from Zod schema
export type Config = z.infer<typeof configSchema>;

/// @notice Individual EVM chain config type
export type EvmConfig = z.infer<typeof evmConfigSchema>;

/// @notice Zod schema for HTTP request payload validation (CRITICAL-003)
export const payloadSchema = z.object({
  operation: z.enum(["DEPOSIT", "WITHDRAW", "REBALANCE_REQUEST"]),
  amount: z.string().regex(/^\d+$/, "Amount must be numeric string"),
  userAddress: z
    .string()
    .startsWith("0x")
    .length(42, "User address must be 42 characters"),
  worldIdProof: z.object({
    root: z.string().min(1, "World ID root required"),
    nullifierHash: z.string().min(1, "Nullifier hash required"),
    proof: z.array(z.string()).length(8, "Proof must have 8 elements"),
  }),
  targetChain: z.string().optional(),
});

/// @notice Inferred payload type
export type Payload = z.infer<typeof payloadSchema>;
