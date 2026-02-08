// AEGIS Protocol - Yield Scanner Config Schema
// Zod validation for CRE workflow configuration (CRITICAL-001)

import { z } from "zod";

/// @notice Zod schema for EVM chain configuration
const evmConfigSchema = z.object({
  vaultAddress: z
    .string()
    .startsWith("0x")
    .length(42, "EVM address must be 42 characters"),
  chainSelectorName: z.string().min(1, "Chain selector name required"),
  gasLimit: z.string().regex(/^\d+$/, "Gas limit must be numeric string"),
});

/// @notice Zod schema for the full yield-scanner config
export const configSchema = z.object({
  groqModel: z.string().min(1, "Groq model name required"),
  schedule: z.string().min(1, "Cron schedule required"),
  rebalanceThresholdBps: z
    .number()
    .int()
    .min(10, "Threshold must be >= 10 bps")
    .max(5000, "Threshold must be <= 5000 bps"),
  evms: z
    .array(evmConfigSchema)
    .min(1, "At least one EVM chain required"),
});

/// @notice Inferred TypeScript type from Zod schema
export type Config = z.infer<typeof configSchema>;

/// @notice Individual EVM chain config type
export type EvmConfig = z.infer<typeof evmConfigSchema>;
