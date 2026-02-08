// AEGIS Protocol - Vault Manager Workflow
// CRE Workflow 3: HTTP-triggered vault operations (deposit/withdraw/rebalance)
// Validates payloads -> checks on-chain state -> writes operation report

import { cre, Runner } from "@chainlink/cre-sdk";
import { configSchema, type Config } from "./configSchema";
import { onHttpTrigger } from "./httpCallback";

// ================================================================
//                  WORKFLOW INITIALIZATION
// ================================================================

/// @notice Initialize the vault manager workflow
/// @dev Sets up HTTP trigger for user-facing vault operations
///      authorizedKeys is empty for hackathon - required for production (CRITICAL-001)
const initWorkflow = (config: Config) => {
  const httpCapability = new cre.capabilities.HTTPCapability();

  // NOTE: For production, add authorizedKeys to restrict who can trigger:
  // httpCapability.trigger({
  //   authorizedKeys: [{
  //     type: "KEY_TYPE_ECDSA_EVM",
  //     publicKey: config.authorizedPublicKey,
  //   }],
  // })
  return [
    cre.handler(
      httpCapability.trigger({}),
      onHttpTrigger,
    ),
  ];
};

// ================================================================
//                       ENTRY POINT
// ================================================================

/// @notice Main entry point for the Vault Manager CRE workflow
/// @dev Uses Zod configSchema for runtime validation
export async function main() {
  const runner = await Runner.newRunner<Config>({ configSchema });
  await runner.run(initWorkflow);
}

main();
