// AEGIS Protocol - Yield Scanner Workflow
// CRE Workflow 1: Cron-triggered yield optimization scanner
// Reads vault state -> Queries Groq AI -> Writes rebalance report

import { cre, Runner } from "@chainlink/cre-sdk";
import { configSchema, type Config } from "./configSchema";
import { onCronTrigger } from "./cronCallback";

// ================================================================
//                  WORKFLOW INITIALIZATION
// ================================================================

/// @notice Initialize the yield scanner workflow
/// @dev Sets up cron trigger with schedule from validated config
const initWorkflow = (config: Config) => {
  const cron = new cre.capabilities.CronCapability();

  return [
    cre.handler(
      cron.trigger({ schedule: config.schedule }),
      onCronTrigger,
    ),
  ];
};

// ================================================================
//                       ENTRY POINT
// ================================================================

/// @notice Main entry point for the Yield Scanner CRE workflow
/// @dev Uses Zod configSchema for runtime validation (CRITICAL-001)
export async function main() {
  const runner = await Runner.newRunner<Config>({ configSchema });
  await runner.run(initWorkflow);
}

main();
