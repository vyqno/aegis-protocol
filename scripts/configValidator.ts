#!/usr/bin/env bun
// AEGIS Protocol - Config Validator
// Validates consistency across all 3 workflow config files (HIGH-001)
// Run: bun run scripts/configValidator.ts

import { readFileSync } from "fs";
import { resolve } from "path";

interface EvmConfig {
  vaultAddress: string;
  riskRegistryAddress?: string;
  worldIdGateAddress?: string;
  chainSelectorName: string;
  gasLimit: string;
}

interface WorkflowConfig {
  evms: EvmConfig[];
  [key: string]: unknown;
}

const ROOT = resolve(import.meta.dir, "..");

// ================================================================
//                    LOAD CONFIGS
// ================================================================

function loadConfig(path: string): WorkflowConfig {
  const fullPath = resolve(ROOT, path);
  const content = readFileSync(fullPath, "utf-8");
  return JSON.parse(content) as WorkflowConfig;
}

// ================================================================
//                    VALIDATION
// ================================================================

let errors = 0;
let warnings = 0;

function error(msg: string) {
  console.error(`  ERROR: ${msg}`);
  errors++;
}

function warn(msg: string) {
  console.warn(`  WARN:  ${msg}`);
  warnings++;
}

function pass(msg: string) {
  console.log(`  PASS:  ${msg}`);
}

console.log("=== AEGIS Protocol Config Validator ===\n");

// Load all configs
console.log("[1/4] Loading config files...");
const yieldConfig = loadConfig("yield-scanner/config.staging.json");
const riskConfig = loadConfig("risk-sentinel/config.staging.json");
const vaultConfig = loadConfig("vault-manager/config.staging.json");
pass("All 3 config files loaded");

// Validate vault addresses match
console.log("\n[2/4] Checking vault address consistency...");
const yieldVault = yieldConfig.evms[0]?.vaultAddress;
const riskVault = riskConfig.evms[0]?.vaultAddress;
const vaultMgrVault = vaultConfig.evms[0]?.vaultAddress;

if (yieldVault === riskVault && riskVault === vaultMgrVault) {
  pass(`All vault addresses match: ${yieldVault}`);
} else {
  error(
    `Vault address mismatch: yield=${yieldVault}, risk=${riskVault}, vault-mgr=${vaultMgrVault}`,
  );
}

// Check for zero addresses (placeholder)
if (yieldVault === "0x0000000000000000000000000000000000000000") {
  warn("Vault address is zero (placeholder) - update before deployment");
}

// Validate chain selectors match
console.log("\n[3/4] Checking chain selector consistency...");
const yieldChain = yieldConfig.evms[0]?.chainSelectorName;
const riskChain = riskConfig.evms[0]?.chainSelectorName;
const vaultChain = vaultConfig.evms[0]?.chainSelectorName;

if (yieldChain === riskChain && riskChain === vaultChain) {
  pass(`All chain selectors match: ${yieldChain}`);
} else {
  error(
    `Chain selector mismatch: yield=${yieldChain}, risk=${riskChain}, vault-mgr=${vaultChain}`,
  );
}

// Validate risk registry address exists in risk-sentinel
console.log("\n[4/4] Checking auxiliary addresses...");
const riskRegistry = (riskConfig.evms[0] as EvmConfig & { riskRegistryAddress?: string })
  ?.riskRegistryAddress;
if (riskRegistry) {
  pass(`Risk registry address configured: ${riskRegistry}`);
  if (riskRegistry === "0x0000000000000000000000000000000000000000") {
    warn("Risk registry address is zero (placeholder) - update before deployment");
  }
} else {
  error("Risk sentinel config missing riskRegistryAddress");
}

const worldIdGate = (vaultConfig.evms[0] as EvmConfig & { worldIdGateAddress?: string })
  ?.worldIdGateAddress;
if (worldIdGate) {
  pass(`WorldIdGate address configured: ${worldIdGate}`);
  if (worldIdGate === "0x0000000000000000000000000000000000000000") {
    warn("WorldIdGate address is zero (placeholder) - update before deployment");
  }
} else {
  error("Vault manager config missing worldIdGateAddress");
}

// Summary
console.log("\n=== Validation Summary ===");
console.log(`  Errors:   ${errors}`);
console.log(`  Warnings: ${warnings}`);

if (errors > 0) {
  console.error("\nFAILED - Fix errors before deploying");
  process.exit(1);
} else if (warnings > 0) {
  console.log("\nPASSED with warnings - update placeholder addresses before deployment");
  process.exit(0);
} else {
  console.log("\nPASSED - all configs are consistent");
  process.exit(0);
}
