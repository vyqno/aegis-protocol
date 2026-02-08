// AEGIS Protocol - Vault Manager HTTP Callback
// Processes user deposit/withdraw requests via HTTP trigger
// Validates payload, checks on-chain state, writes vault operation report

import {
  cre,
  type Runtime,
  type HTTPPayload,
  getNetwork,
  LAST_FINALIZED_BLOCK_NUMBER,
  bytesToHex,
  hexToBase64,
  encodeCallMsg,
  decodeJson,
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
import { payloadSchema, type Payload } from "./configSchema";

// ================================================================
//                    ABI FRAGMENTS
// ================================================================

/// @notice Minimal ABI for vault reads
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
  {
    type: "function",
    name: "isSetupComplete",
    inputs: [],
    outputs: [{ type: "bool", name: "" }],
    stateMutability: "view",
  },
] as const;

// ================================================================
//                    ON-CHAIN READS
// ================================================================

/// @notice Read vault state for pre-flight checks
function readVaultState(
  runtime: Runtime<Config>,
  evmClient: InstanceType<typeof cre.capabilities.EVMClient>,
  vaultAddress: Address,
): { cbActive: boolean; totalAssets: bigint; setupComplete: boolean } {
  // Read circuit breaker status
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

  // Read total assets
  const assetsCall = encodeFunctionData({
    abi: VAULT_ABI,
    functionName: "getTotalAssets",
  });
  const assetsResp = evmClient
    .callContract(runtime, {
      call: encodeCallMsg({
        from: zeroAddress,
        to: vaultAddress,
        data: assetsCall,
      }),
      blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
    })
    .result();
  const totalAssets = decodeFunctionResult({
    abi: VAULT_ABI,
    functionName: "getTotalAssets",
    data: bytesToHex(assetsResp.data),
  }) as bigint;

  // Read setup status
  const setupCall = encodeFunctionData({
    abi: VAULT_ABI,
    functionName: "isSetupComplete",
  });
  const setupResp = evmClient
    .callContract(runtime, {
      call: encodeCallMsg({
        from: zeroAddress,
        to: vaultAddress,
        data: setupCall,
      }),
      blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
    })
    .result();
  const setupComplete = decodeFunctionResult({
    abi: VAULT_ABI,
    functionName: "isSetupComplete",
    data: bytesToHex(setupResp.data),
  }) as boolean;

  return { cbActive, totalAssets, setupComplete };
}

// ================================================================
//                    REPORT WRITER
// ================================================================

/// @notice Write vault operation report
/// @dev Report format: 0x03 (prefix) + abi.encode(uint8 opType, address user, uint256 amount)
function writeVaultReport(
  runtime: Runtime<Config>,
  evmClient: InstanceType<typeof cre.capabilities.EVMClient>,
  evmConfig: EvmConfig,
  opType: number,
  userAddress: string,
  amount: string,
): string {
  const vaultAddress = getAddress(evmConfig.vaultAddress);

  // Encode report payload
  const reportPayload = encodeAbiParameters(
    parseAbiParameters("uint8 opType, address user, uint256 amount"),
    [opType, getAddress(userAddress) as Address, BigInt(amount)],
  );

  // Prepend 0x03 prefix (vault operation type)
  const fullReport = ("0x03" + reportPayload.slice(2)) as `0x${string}`;

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
    // Check errorMessage even on SUCCESS (MEDIUM-004)
    if (writeResult.errorMessage?.includes("revert")) {
      throw new Error(`Consumer reverted: ${writeResult.errorMessage}`);
    }
    const txHash = bytesToHex(
      writeResult.txHash || new Uint8Array(32),
    );
    runtime.log(`[Write] Vault report delivered: ${txHash}`);
    return txHash;
  }

  throw new Error(
    `Transaction failed: ${writeResult.txStatus} - ${writeResult.errorMessage || "unknown"}`,
  );
}

// ================================================================
//                    HTTP HANDLER (EXPORTED)
// ================================================================

/// @notice Main HTTP trigger handler for vault operations
/// @dev Validates payload -> checks on-chain state -> writes report
export function onHttpTrigger(
  runtime: Runtime<Config>,
  payload: HTTPPayload,
): string {
  runtime.log("[HTTP] Vault Manager triggered");

  // Step 1: Decode and validate payload with Zod (CRITICAL-003)
  let parsed: Payload;
  try {
    const rawInput = decodeJson(payload.input) as unknown;
    parsed = payloadSchema.parse(rawInput);
  } catch (err) {
    runtime.log(`[Reject] Invalid payload: ${err}`);
    return JSON.stringify({ error: "Invalid payload", status: "REJECTED" });
  }

  // Step 2: Checksum addresses (MEDIUM-001)
  const checksummedUser = getAddress(parsed.userAddress);
  runtime.log(
    `[HTTP] Operation: ${parsed.operation}, User: ${checksummedUser}, Amount: ${parsed.amount}`,
  );

  // Step 3: Resolve network and create EVM client
  const evmConfig = runtime.config.evms[0];
  const network = getNetwork({
    chainFamily: "evm",
    chainSelectorName: evmConfig.chainSelectorName,
    isTestnet: evmConfig.chainSelectorName.includes("testnet"),
  });

  if (!network) {
    runtime.log(
      `[Error] Network not found: ${evmConfig.chainSelectorName}`,
    );
    return JSON.stringify({ error: "Network not found", status: "ERROR" });
  }

  const evmClient = new cre.capabilities.EVMClient(
    network.chainSelector.selector,
  );
  const vaultAddress = getAddress(evmConfig.vaultAddress) as Address;

  // Step 4: Read on-chain state for pre-flight checks
  const vaultState = readVaultState(runtime, evmClient, vaultAddress);

  // Check setup complete
  if (!vaultState.setupComplete) {
    runtime.log("[Reject] Vault setup not complete");
    return JSON.stringify({ error: "Vault setup not complete", status: "REJECTED" });
  }

  // Check circuit breaker
  if (vaultState.cbActive) {
    runtime.log("[Reject] Circuit breaker active - all operations blocked");
    return JSON.stringify({ error: "Circuit breaker active", status: "REJECTED" });
  }

  // Step 5: Operation-specific pre-flight checks (UX-only, HIGH-002)
  // NOTE: On-chain contract performs authoritative validation
  if (parsed.operation === "WITHDRAW") {
    // Off-chain balance check is UX-only - prevents wasted gas
    // AegisVault.withdraw() performs the authoritative on-chain check
    if (vaultState.totalAssets === 0n) {
      runtime.log("[Reject] Vault has no assets (off-chain UX check)");
      return JSON.stringify({ error: "Vault empty", status: "REJECTED" });
    }
  }

  if (parsed.operation === "DEPOSIT") {
    if (BigInt(parsed.amount) === 0n) {
      runtime.log("[Reject] Zero deposit amount");
      return JSON.stringify({ error: "Zero amount", status: "REJECTED" });
    }
  }

  // Step 6: Encode operation type
  let opType: number;
  switch (parsed.operation) {
    case "DEPOSIT":
      opType = 1;
      break;
    case "WITHDRAW":
      opType = 2;
      break;
    case "REBALANCE_REQUEST":
      opType = 3;
      break;
  }

  // Step 7: Write vault operation report to chain
  runtime.log(
    `[Action] Writing ${parsed.operation} report for ${checksummedUser}`,
  );

  const txHash = writeVaultReport(
    runtime,
    evmClient,
    evmConfig,
    opType,
    parsed.userAddress,
    parsed.amount,
  );

  runtime.log(`[Done] ${parsed.operation} report tx=${txHash}`);

  return JSON.stringify({
    operation: parsed.operation,
    user: checksummedUser,
    amount: parsed.amount,
    txHash,
    status: "SUCCESS",
  });
}
