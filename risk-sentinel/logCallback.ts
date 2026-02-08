// AEGIS Protocol - Risk Sentinel Log Callback
// Triggered by RiskAlertCreated events from RiskRegistry
// Reads vault state, calls Groq AI, writes risk report to AegisVault

import {
  cre,
  type Runtime,
  type EVMLog,
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
  decodeEventLog,
  encodeAbiParameters,
  parseAbiParameters,
  zeroAddress,
  getAddress,
  type Address,
} from "viem";
import type { Config, EvmConfig } from "./configSchema";
import { askGroqRisk, type RiskAssessment } from "./groqRisk";

// ================================================================
//                    ABI FRAGMENTS
// ================================================================

/// @notice RiskAlertCreated event ABI for decoding
const RISK_ALERT_EVENT_ABI = [
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
] as const;

/// @notice Minimal ABI for vault/registry reads
const VAULT_ABI = [
  {
    type: "function",
    name: "isCircuitBreakerActive",
    inputs: [],
    outputs: [{ type: "bool", name: "" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getTotalAssets",
    inputs: [],
    outputs: [{ type: "uint256", name: "" }],
    stateMutability: "view",
  },
] as const;

const REGISTRY_ABI = [
  {
    type: "function",
    name: "isCircuitBreakerActive",
    inputs: [],
    outputs: [{ type: "bool", name: "" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "riskThreshold",
    inputs: [],
    outputs: [{ type: "uint256", name: "" }],
    stateMutability: "view",
  },
] as const;

// ================================================================
//                    IDEMPOTENCY CHECK
// ================================================================

/// @notice Check if circuit breaker is already active (CRITICAL-002)
/// @dev Prevents redundant activations and saves API credits
function isCircuitBreakerAlreadyActive(
  runtime: Runtime<Config>,
  evmClient: InstanceType<typeof cre.capabilities.EVMClient>,
  vaultAddress: Address,
): boolean {
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

  return decodeFunctionResult({
    abi: VAULT_ABI,
    functionName: "isCircuitBreakerActive",
    data: bytesToHex(cbResp.data),
  }) as boolean;
}

/// @notice Read vault total assets
function readVaultAssets(
  runtime: Runtime<Config>,
  evmClient: InstanceType<typeof cre.capabilities.EVMClient>,
  vaultAddress: Address,
): bigint {
  const call = encodeFunctionData({
    abi: VAULT_ABI,
    functionName: "getTotalAssets",
  });

  const resp = evmClient
    .callContract(runtime, {
      call: encodeCallMsg({
        from: zeroAddress,
        to: vaultAddress,
        data: call,
      }),
      blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
    })
    .result();

  return decodeFunctionResult({
    abi: VAULT_ABI,
    functionName: "getTotalAssets",
    data: bytesToHex(resp.data),
  }) as bigint;
}

// ================================================================
//                    REPORT WRITER
// ================================================================

/// @notice Write risk report to AegisVault via CRE signed report
/// @dev Report format: 0x02 (prefix) + abi.encode(bool shouldActivate, uint256 riskScore)
function writeRiskReport(
  runtime: Runtime<Config>,
  evmClient: InstanceType<typeof cre.capabilities.EVMClient>,
  evmConfig: EvmConfig,
  shouldActivate: boolean,
  riskScore: number,
): string {
  const vaultAddress = getAddress(evmConfig.vaultAddress);

  // Encode report payload: abi.encode(bool shouldActivate, uint256 riskScore)
  const reportPayload = encodeAbiParameters(
    parseAbiParameters("bool shouldActivate, uint256 riskScore"),
    [shouldActivate, BigInt(riskScore)],
  );

  // Prepend 0x02 prefix (risk report type)
  const fullReport = ("0x02" + reportPayload.slice(2)) as `0x${string}`;

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

  if (writeResult.txStatus === TxStatus.SUCCESS) {
    // Check errorMessage even on SUCCESS (MEDIUM-001 from Phase 07)
    if (writeResult.errorMessage?.includes("revert")) {
      throw new Error(`Consumer reverted: ${writeResult.errorMessage}`);
    }

    const txHash = bytesToHex(
      writeResult.txHash || new Uint8Array(32),
    );
    runtime.log(`[Write] Risk report delivered: ${txHash}`);
    return txHash;
  }

  throw new Error(
    `Transaction failed: ${writeResult.txStatus} - ${writeResult.errorMessage || "unknown"}`,
  );
}

// ================================================================
//                    LOG TRIGGER HANDLER (EXPORTED)
// ================================================================

/// @notice Main log trigger handler - processes RiskAlertCreated events
/// @dev Reads event data -> checks idempotency -> threshold pre-check -> Groq AI -> writes report
export function onLogTrigger(
  runtime: Runtime<Config>,
  log: EVMLog,
): string {
  runtime.log("[Log] Risk Sentinel triggered by RiskAlertCreated event");

  // Decode event log
  const topics = log.topics.map((t) => bytesToHex(t)) as [
    `0x${string}`,
    ...`0x${string}`[],
  ];
  const data = bytesToHex(log.data);

  let protocol: string;
  let score: bigint;
  let threshold: bigint;
  let alertNumber: bigint;

  try {
    const decoded = decodeEventLog({
      abi: RISK_ALERT_EVENT_ABI,
      data,
      topics,
    });
    protocol = decoded.args.protocol;
    score = decoded.args.score;
    threshold = decoded.args.threshold;
    alertNumber = decoded.args.alertNumber;
  } catch (err) {
    runtime.log(`[Error] Failed to decode event: ${err}`);
    return "Failed to decode event - HOLD";
  }

  runtime.log(
    `[Event] Protocol: ${protocol}, Score: ${score}, Threshold: ${threshold}, Alert #${alertNumber}`,
  );

  // Use first configured EVM chain
  const evmConfig = runtime.config.evms[0];

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
    return "Network not found - HOLD";
  }

  const evmClient = new cre.capabilities.EVMClient(
    network.chainSelector.selector,
  );
  const vaultAddress = getAddress(evmConfig.vaultAddress) as Address;

  // Step 1: Idempotency check - skip if CB already active (CRITICAL-002)
  if (isCircuitBreakerAlreadyActive(runtime, evmClient, vaultAddress)) {
    runtime.log("[Skip] Circuit breaker already active - no action needed");
    return "CB already active - HOLD";
  }

  // Step 2: Quick threshold pre-check before calling AI (HIGH-001)
  // If risk score is well below threshold, skip AI call to save credits
  const scoreNum = Number(score);
  const thresholdNum = Number(threshold);
  if (scoreNum < thresholdNum * 0.7) {
    runtime.log(
      `[Skip] Score ${scoreNum} well below threshold ${thresholdNum} (70%) - no AI needed`,
    );
    return `Low risk (${scoreNum}/${thresholdNum}) - HOLD`;
  }

  // Step 3: Read vault state for AI context
  const totalAssets = readVaultAssets(runtime, evmClient, vaultAddress);

  // Step 4: Build risk data context for AI analysis
  const riskDataStr = [
    `Risk Alert #${alertNumber} for protocol ${protocol}`,
    `Current Risk Score: ${scoreNum} / 10000 (${(scoreNum / 100).toFixed(1)}%)`,
    `Risk Threshold: ${thresholdNum} / 10000 (${(thresholdNum / 100).toFixed(1)}%)`,
    `Vault Total Assets: ${totalAssets.toString()} wei (${Number(totalAssets) / 1e18} ETH)`,
    `Health Factor Min Threshold: ${runtime.config.thresholds.healthFactorMin}`,
    `Max Acceptable Risk Score: ${runtime.config.thresholds.riskScoreMax}`,
  ].join("\n");

  // Step 5: Query Groq AI for risk assessment (with HOLD fallback, MEDIUM-004)
  let assessment: RiskAssessment;
  try {
    const groqApiKey = runtime
      .getSecret({ id: "GROQ_API_KEY" })
      .result();
    assessment = askGroqRisk(runtime, riskDataStr, groqApiKey.value);
  } catch (err) {
    runtime.log(
      `[WARN] AI unavailable: ${err}. Defaulting to HOLD.`,
    );
    return "AI unavailable - HOLD";
  }

  // Step 6: Determine if circuit breaker should activate
  const shouldActivate =
    assessment.action === "EMERGENCY_EXIT" ||
    assessment.action === "DELEVERAGE";

  // Step 7: Require minimum confidence for activation (CRITICAL-001)
  if (shouldActivate && assessment.confidence < 7000) {
    runtime.log(
      `[Skip] Action ${assessment.action} confidence ${assessment.confidence} < 7000 - defaulting to HOLD`,
    );
    return `Low confidence (${assessment.confidence}) for ${assessment.action} - HOLD`;
  }

  // Step 8: Write risk report
  if (shouldActivate) {
    runtime.log(
      `[Action] ${assessment.action} (severity: ${assessment.severity}, confidence: ${assessment.confidence})`,
    );

    const txHash = writeRiskReport(
      runtime,
      evmClient,
      evmConfig,
      true,
      scoreNum,
    );

    return `${assessment.action} (confidence: ${assessment.confidence}) tx=${txHash}`;
  }

  // HOLD - no report needed
  runtime.log(
    `[Hold] AI recommends HOLD (confidence: ${assessment.confidence}) - no report written`,
  );
  return `HOLD (confidence: ${assessment.confidence})`;
}
