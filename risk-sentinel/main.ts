// AEGIS Protocol - Risk Sentinel Workflow
// CRE Workflow 2: Log-triggered risk monitoring and circuit breaker activation
// Monitors RiskAlertCreated events -> Queries Groq AI -> Writes risk report

import {
  cre,
  Runner,
  getNetwork,
  bytesToHex,
} from "@chainlink/cre-sdk";
import { toEventHash } from "viem";
import { configSchema, type Config } from "./configSchema";
import { onLogTrigger } from "./logCallback";

// ================================================================
//                    EVENT SIGNATURE
// ================================================================

/// @notice RiskAlertCreated event signature hash
/// @dev keccak256("RiskAlertCreated(address,uint256,uint256,uint256,uint256)")
const RISK_ALERT_EVENT_HASH = toEventHash(
  "event RiskAlertCreated(address indexed protocol, uint256 score, uint256 threshold, uint256 alertNumber, uint256 timestamp)",
);

// ================================================================
//                  WORKFLOW INITIALIZATION
// ================================================================

/// @notice Initialize the risk sentinel workflow
/// @dev Sets up log trigger monitoring RiskAlertCreated events from RiskRegistry
const initWorkflow = (config: Config) => {
  const evmConfig = config.evms[0];

  // Resolve network for log trigger
  const network = getNetwork({
    chainFamily: "evm",
    chainSelectorName: evmConfig.chainSelectorName,
    isTestnet: evmConfig.chainSelectorName.includes("testnet"),
  });

  if (!network) {
    throw new Error(
      `Network not found: ${evmConfig.chainSelectorName}`,
    );
  }

  const evmClient = new cre.capabilities.EVMClient(
    network.chainSelector.selector,
  );

  return [
    cre.handler(
      evmClient.logTrigger({
        addresses: [evmConfig.riskRegistryAddress],
        topics: [{ values: [RISK_ALERT_EVENT_HASH] }],
        confidence: "CONFIDENCE_LEVEL_FINALIZED",
      }),
      onLogTrigger,
    ),
  ];
};

// ================================================================
//                       ENTRY POINT
// ================================================================

/// @notice Main entry point for the Risk Sentinel CRE workflow
/// @dev Uses Zod configSchema for runtime validation
export async function main() {
  const runner = await Runner.newRunner<Config>({ configSchema });
  await runner.run(initWorkflow);
}

main();
