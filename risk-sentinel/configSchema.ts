// AEGIS Protocol - Risk Sentinel Config Schema
// Zod validation for CRE workflow configuration (MEDIUM-001)

import { z } from "zod";

/// @notice Zod schema for EVM chain configuration
const evmConfigSchema = z.object({
  vaultAddress: z
    .string()
    .startsWith("0x")
    .length(42, "EVM address must be 42 characters"),
  riskRegistryAddress: z
    .string()
    .startsWith("0x")
    .length(42, "EVM address must be 42 characters"),
  chainSelectorName: z.string().min(1, "Chain selector name required"),
  gasLimit: z.string().regex(/^\d+$/, "Gas limit must be numeric string"),
});

/// @notice Zod schema for risk thresholds
const thresholdsSchema = z.object({
  healthFactorMin: z.string().min(1, "Health factor threshold required"),
  riskScoreMax: z
    .number()
    .int()
    .min(0, "Risk score min must be >= 0")
    .max(10000, "Risk score max must be <= 10000"),
});

/// @notice Zod schema for the full risk-sentinel config
export const configSchema = z.object({
  groqModel: z.string().min(1, "Groq model name required"),
  evms: z
    .array(evmConfigSchema)
    .min(1, "At least one EVM chain required"),
  thresholds: thresholdsSchema,
});

/// @notice Inferred TypeScript type from Zod schema
export type Config = z.infer<typeof configSchema>;

/// @notice Individual EVM chain config type
export type EvmConfig = z.infer<typeof evmConfigSchema>;
