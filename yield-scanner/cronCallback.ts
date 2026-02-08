// AEGIS Protocol - Yield Scanner Cron Callback
// Reads vault state, calls Groq AI, writes yield report to AegisVault

import {
  cre,
  type Runtime,
  type CronPayload,
  getNetwork,
  LAST_FINALIZED_BLOCK_NUMBER,
  bytesToHex,
  hexToBase64,
  encodeCallMsg,
  TxStatus,
} from "@chainlink/cre-sdk";
import {
  encodeFunctionData,
  decodeFunctionResult,
  encodeAbiParameters,
  parseAbiParameters,
  zeroAddress,
  getAddress,
  type Address,
} from "viem";
import type { Config, EvmConfig } from "./configSchema";
import { askGroq, type YieldAnalysis } from "./groqAi";

// ================================================================
//                    ABI FRAGMENTS
// ================================================================

/// @notice Minimal ABI for AegisVault read functions
const VAULT_ABI = [
  {
    type: "function",
    name: "getTotalAssets",
    inputs: [],
    outputs: [{ type: "uint256", name: "" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "isCircuitBreakerActive",
    inputs: [],
    outputs: [{ type: "bool", name: "" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "totalShares",
    inputs: [],
    outputs: [{ type: "uint256", name: "" }],
    stateMutability: "view",
  },
] as const;

// ================================================================
//                    ON-CHAIN DATA READER
// ================================================================

/// @notice Read vault state from on-chain using LAST_FINALIZED_BLOCK_NUMBER (HIGH-001)
function readVaultState(
  runtime: Runtime<Config>,
  evmClient: InstanceType<typeof cre.capabilities.EVMClient>,
  vaultAddress: Address,
): { totalAssets: bigint; cbActive: boolean; totalShares: bigint } {
  // Read getTotalAssets
  const totalAssetsCall = encodeFunctionData({
    abi: VAULT_ABI,
    functionName: "getTotalAssets",
  });

  const totalAssetsResp = evmClient
    .callContract(runtime, {
      call: encodeCallMsg({
        from: zeroAddress,
        to: vaultAddress,
        data: totalAssetsCall,
      }),
      blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
    })
    .result();

  const totalAssets = decodeFunctionResult({
    abi: VAULT_ABI,
    functionName: "getTotalAssets",
    data: bytesToHex(totalAssetsResp.data),
  }) as bigint;

  // Read isCircuitBreakerActive
  const cbCall = encodeFunctionData({
    abi: VAULT_ABI,
    functionName: "isCircuitBreakerActive",
  });

  const cbResp = evmClient
    .callContract(runtime, {
      call: encodeCallMsg({
        from: zeroAddress,
        to: vaultAddress,
        data: cbCall,
      }),
      blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
    })
    .result();

  const cbActive = decodeFunctionResult({
    abi: VAULT_ABI,
    functionName: "isCircuitBreakerActive",
    data: bytesToHex(cbResp.data),
  }) as boolean;

  // Read totalShares
  const sharesCall = encodeFunctionData({
    abi: VAULT_ABI,
    functionName: "totalShares",
  });

  const sharesResp = evmClient
    .callContract(runtime, {
      call: encodeCallMsg({
        from: zeroAddress,
        to: vaultAddress,
        data: sharesCall,
      }),
      blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
    })
    .result();

  const totalShares = decodeFunctionResult({
    abi: VAULT_ABI,
    functionName: "totalShares",
    data: bytesToHex(sharesResp.data),
  }) as bigint;

  return { totalAssets, cbActive, totalShares };
}

// ================================================================
//                    REPORT WRITER
// ================================================================

/// @notice Write yield report to AegisVault via CRE signed report
/// @dev Report format: 0x01 (prefix) + abi.encode(uint256 confidence)
function writeYieldReport(
  runtime: Runtime<Config>,
  evmClient: InstanceType<typeof cre.capabilities.EVMClient>,
  evmConfig: EvmConfig,
  analysis: YieldAnalysis,
): string {
  // Checksum the vault address (MEDIUM-002)
  const vaultAddress = getAddress(evmConfig.vaultAddress);

  // Encode report payload: abi.encode(uint256 confidence)
  const reportPayload = encodeAbiParameters(
    parseAbiParameters("uint256 confidence"),
    [BigInt(analysis.confidence)],
  );

  // Prepend 0x01 prefix (yield report type)
  const fullReport = ("0x01" + reportPayload.slice(2)) as `0x${string}`;

  // Generate signed CRE report
  const reportResponse = runtime
    .report({
      encodedPayload: hexToBase64(fullReport),
      encoderName: "evm",
      signingAlgo: "ecdsa",
      hashingAlgo: "keccak256",
    })
    .result();

  // Write report to vault contract
  const writeResult = evmClient
    .writeReport(runtime, {
      receiver: vaultAddress,
      report: reportResponse,
      gasConfig: {
        gasLimit: evmConfig.gasLimit,
      },
    })
    .result();

  // Check transaction status
  if (writeResult.txStatus === TxStatus.SUCCESS) {
    // MEDIUM-001: Check errorMessage even on SUCCESS
    // Forwarder tx may succeed while consumer call fails
    if (writeResult.errorMessage?.includes("revert")) {
      throw new Error(`Consumer reverted: ${writeResult.errorMessage}`);
    }

    const txHash = bytesToHex(
      writeResult.txHash || new Uint8Array(32),
    );
    runtime.log(`[Write] Report delivered: ${txHash}`);
    return txHash;
  }

  throw new Error(
    `Transaction failed: ${writeResult.txStatus} - ${writeResult.errorMessage || "unknown"}`,
  );
}

// ================================================================
//                    CRON HANDLER (EXPORTED)
// ================================================================

/// @notice Main cron trigger handler
/// @dev Reads vault state -> queries Groq AI -> writes report (if REBALANCE)
export function onCronTrigger(
  runtime: Runtime<Config>,
  payload: CronPayload,
): string {
  // Validate cron payload (MEDIUM-004)
  if (!payload.scheduledExecutionTime) {
    throw new Error("Missing scheduled execution time");
  }

  runtime.log(
    `[Cron] Yield Scanner triggered at ${payload.scheduledExecutionTime}`,
  );

  // Get Groq API key from CRE secrets (HIGH-002)
  const groqApiKey = runtime.getSecret({ id: "GROQ_API_KEY" }).result();

  // Process each configured EVM chain
  const results: string[] = [];

  for (const evmConfig of runtime.config.evms) {
    runtime.log(
      `[Chain] Processing ${evmConfig.chainSelectorName}`,
    );

    // Resolve network
    const network = getNetwork({
      chainFamily: "evm",
      chainSelectorName: evmConfig.chainSelectorName,
      isTestnet: evmConfig.chainSelectorName.includes("testnet"),
    });

    if (!network) {
      runtime.log(
        `[Error] Network not found: ${evmConfig.chainSelectorName}`,
      );
      continue;
    }

    // Initialize EVM client
    const evmClient = new cre.capabilities.EVMClient(
      network.chainSelector.selector,
    );

    // Checksum vault address (MEDIUM-002)
    const vaultAddress = getAddress(evmConfig.vaultAddress) as Address;

    // Step 1: Read vault state from finalized block (HIGH-001)
    const vaultState = readVaultState(
      runtime,
      evmClient,
      vaultAddress,
    );

    runtime.log(
      `[Read] Assets: ${vaultState.totalAssets}, Shares: ${vaultState.totalShares}, CB: ${vaultState.cbActive}`,
    );

    // Skip if circuit breaker is active
    if (vaultState.cbActive) {
      runtime.log("[Skip] Circuit breaker active - no action");
      results.push(`${evmConfig.chainSelectorName}: CB_ACTIVE`);
      continue;
    }

    // Skip if vault has no assets
    if (vaultState.totalAssets === 0n) {
      runtime.log("[Skip] Vault has no assets - no action");
      results.push(`${evmConfig.chainSelectorName}: NO_ASSETS`);
      continue;
    }

    // Step 2: Build vault data context for AI analysis
    const vaultDataStr = [
      `Vault Total Assets: ${vaultState.totalAssets.toString()} wei (${Number(vaultState.totalAssets) / 1e18} ETH)`,
      `Vault Total Shares: ${vaultState.totalShares.toString()}`,
      `Circuit Breaker: ${vaultState.cbActive ? "ACTIVE" : "INACTIVE"}`,
      `Chain: ${evmConfig.chainSelectorName}`,
      `Rebalance Threshold: ${runtime.config.rebalanceThresholdBps} bps`,
      `Timestamp: ${payload.scheduledExecutionTime}`,
    ].join("\n");

    // Step 3: Query Groq AI for yield analysis (CRITICAL-003 defense in system prompt)
    const analysis = askGroq(runtime, vaultDataStr, groqApiKey.value);

    // Step 4: Only write report if REBALANCE with sufficient confidence (MEDIUM-003)
    if (analysis.action === "HOLD") {
      runtime.log(
        `[Skip] AI recommends HOLD (confidence: ${analysis.confidence}) - no report written`,
      );
      results.push(
        `${evmConfig.chainSelectorName}: HOLD (${analysis.confidence})`,
      );
      continue;
    }

    // Check confidence threshold
    if (analysis.confidence < 5000) {
      runtime.log(
        `[Skip] Confidence too low: ${analysis.confidence} < 5000 - defaulting to HOLD`,
      );
      results.push(
        `${evmConfig.chainSelectorName}: LOW_CONFIDENCE (${analysis.confidence})`,
      );
      continue;
    }

    // Step 5: Write yield report to vault
    const txHash = writeYieldReport(
      runtime,
      evmClient,
      evmConfig,
      analysis,
    );

    results.push(
      `${evmConfig.chainSelectorName}: REBALANCE (${analysis.confidence}) tx=${txHash}`,
    );
  }

  const summary = results.join(" | ");
  runtime.log(`[Done] ${summary}`);
  return summary;
}
