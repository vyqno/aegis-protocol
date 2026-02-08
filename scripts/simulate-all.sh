#!/bin/bash
# AEGIS Protocol - Simulate All Workflows
# Run from project root: bash scripts/simulate-all.sh

set -e

echo "=== AEGIS Protocol - Workflow Simulation ==="
echo ""

# Step 1: Validate configs
echo "[1/4] Validating config consistency..."
bun run scripts/configValidator.ts
echo ""

# Step 2: Simulate Yield Scanner (Cron Trigger)
echo "[2/4] Simulating Yield Scanner..."
cre workflow simulate yield-scanner --target staging-settings
echo "Yield Scanner: OK"
echo ""

# Step 3: Simulate Risk Sentinel (Log Trigger)
echo "[3/4] Simulating Risk Sentinel..."
cre workflow simulate risk-sentinel --target staging-settings
echo "Risk Sentinel: OK"
echo ""

# Step 4: Simulate Vault Manager (HTTP Trigger)
echo "[4/4] Simulating Vault Manager..."
cre workflow simulate vault-manager --target staging-settings
echo "Vault Manager: OK"
echo ""

echo "=== All 3 workflows simulated successfully ==="
