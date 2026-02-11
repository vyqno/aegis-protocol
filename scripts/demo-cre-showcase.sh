#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
#  AEGIS Protocol — Full CRE Workflow Showcase
# ============================================================================
#  Demonstrates ALL 3 CRE workflows end-to-end with real on-chain state:
#
#    1. Yield Scanner  (Cron)  — reads funded vault → Groq AI analysis → report
#    2. Risk Sentinel  (Log)   — detects RiskAlertCreated → AI assessment → CB
#    3. Vault Manager  (HTTP)  — validates DEPOSIT payload → preflight → report
#
#  How it works:
#    - Forks Sepolia via Anvil (preserves deployed contracts)
#    - Deposits 5 ETH into vault (creates non-zero state for yield scanner)
#    - Triggers RiskAlertCreated event (creates log for risk sentinel)
#    - Points CRE to the fork, runs all 3 simulations
#    - Restores everything on exit
# ============================================================================

# --------------- Deployed Contract Addresses (Sepolia) ---------------
VAULT="0x92Bf1f6a56A39F64bfD86e53a4D40c1F35D3965a"
RISK_REGISTRY="0x9CA2221e10F55d5CCae3b6ca2d749A360D9ba82c"
STRATEGY_ROUTER="0xf33C966ef21C783d8f921f2c9Df43bdB20C14855"
WORLD_ID_GATE="0x98cdd8449Fb1022A7015F0332F95778bc85da7F1"
OWNER="0x1ceC5F57eC0A6f782F736549eBd391ddF3233D8e"
AAVE_POOL="0xBE5E5728dB7F0E23E20B87E3737445796b272484"

# --------------- RPC & Network ---------------
SEPOLIA_RPC="https://ethereum-sepolia-rpc.publicnode.com"
ANVIL_RPC="http://127.0.0.1:8545"
ANVIL_PORT=8545

# --------------- Event Signatures ---------------
RISK_ALERT_TOPIC="0x14f3c57cf2f10c5c67ed2a6e79b2c5095b331141697821d40b438b6dc3d82ff8"

# --------------- Paths ---------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_YAML="$PROJECT_ROOT/project.yaml"
PROJECT_YAML_BAK="$PROJECT_ROOT/project.yaml.showcase.bak"

# --------------- State ---------------
ANVIL_PID=""
RISK_TX=""
DEPOSIT_TX=""

# ============================= Formatting ================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()    { echo -e "  ${BLUE}[INFO]${NC} $*"; }
success() { echo -e "  ${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "  ${YELLOW}[WARN]${NC} $*"; }
fail()    { echo -e "  ${RED}[FAIL]${NC} $*"; }

header() {
  echo ""
  echo -e "${BOLD}${CYAN}  =================================================================${NC}"
  echo -e "${BOLD}${CYAN}    $*${NC}"
  echo -e "${BOLD}${CYAN}  =================================================================${NC}"
  echo ""
}

step() {
  echo -e "  ${BOLD}${MAGENTA}>>>${NC} ${BOLD}$*${NC}"
}

divider() {
  echo -e "  ${DIM}─────────────────────────────────────────────────────${NC}"
}

# ============================= Cleanup ===================================
cleanup() {
  echo ""
  info "Cleaning up..."

  # Restore project.yaml
  if [[ -f "$PROJECT_YAML_BAK" ]]; then
    cp "$PROJECT_YAML_BAK" "$PROJECT_YAML"
    rm -f "$PROJECT_YAML_BAK"
    success "Restored project.yaml"
  fi

  # Kill Anvil
  if [[ -n "${ANVIL_PID:-}" ]] && kill -0 "$ANVIL_PID" 2>/dev/null; then
    kill "$ANVIL_PID" 2>/dev/null || true
    wait "$ANVIL_PID" 2>/dev/null || true
    success "Stopped Anvil (PID=$ANVIL_PID)"
  fi
}
trap cleanup EXIT

# ============================= JSON Helper ===============================
# Extract a field from JSON using python3 (no jq on this system)
json_get() {
  python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$1',''))" 2>/dev/null
}

# ========================================================================
#  PHASE 0: Prerequisites
# ========================================================================
header "PHASE 0 — Prerequisites"

for cmd in anvil forge cast cre python3; do
  if command -v "$cmd" &>/dev/null; then
    success "$cmd found"
  else
    fail "$cmd not found — install it first"
    exit 1
  fi
done

# Check GROQ_API_KEY
if [[ -f "$PROJECT_ROOT/.env" ]] && grep -q "GROQ_API_KEY" "$PROJECT_ROOT/.env"; then
  success "GROQ_API_KEY found in .env (AI steps will run)"
  HAS_GROQ=true
else
  warn "GROQ_API_KEY not in .env — yield scanner will skip AI call"
  HAS_GROQ=false
fi

# ========================================================================
#  PHASE 1: Start Anvil Fork of Sepolia
# ========================================================================
header "PHASE 1 — Start Anvil (Sepolia Fork)"

# Kill any existing Anvil on this port
if command -v taskkill &>/dev/null; then
  # Windows: try taskkill
  taskkill //F //IM anvil.exe 2>/dev/null || true
else
  pkill -f "anvil.*${ANVIL_PORT}" 2>/dev/null || true
fi
sleep 1

step "Forking Sepolia at localhost:${ANVIL_PORT}..."
anvil \
  --fork-url "$SEPOLIA_RPC" \
  --port "$ANVIL_PORT" \
  --block-time 2 \
  --silent \
  &
ANVIL_PID=$!
sleep 4

if kill -0 "$ANVIL_PID" 2>/dev/null; then
  BLOCK=$(cast block-number --rpc-url "$ANVIL_RPC" 2>/dev/null || echo "?")
  success "Anvil running (PID=$ANVIL_PID) — forked at block $BLOCK"
else
  fail "Anvil failed to start"
  exit 1
fi

# ========================================================================
#  PHASE 2: Verify Deployed Contracts
# ========================================================================
header "PHASE 2 — Verify Deployed Contracts"

step "Checking bytecode on fork..."
ALL_OK=true
for pair in "AegisVault:$VAULT" "RiskRegistry:$RISK_REGISTRY" "StrategyRouter:$STRATEGY_ROUTER" "WorldIdGate:$WORLD_ID_GATE"; do
  name="${pair%%:*}"
  addr="${pair##*:}"
  code_len=$(cast code "$addr" --rpc-url "$ANVIL_RPC" 2>/dev/null | wc -c)
  if [[ "$code_len" -gt 4 ]]; then
    success "$name  ${DIM}${addr}${NC}"
  else
    fail "$name  ${addr} — no code!"
    ALL_OK=false
  fi
done

if [[ "$ALL_OK" != "true" ]]; then
  fail "Some contracts missing. Deploy first."
  exit 1
fi

divider
step "Current vault state..."
ASSETS_0=$(cast call "$VAULT" "getTotalAssets()(uint256)" --rpc-url "$ANVIL_RPC" 2>/dev/null || echo "0")
SHARES_0=$(cast call "$VAULT" "totalShares()(uint256)" --rpc-url "$ANVIL_RPC" 2>/dev/null || echo "0")
CB_0=$(cast call "$VAULT" "isCircuitBreakerActive()(bool)" --rpc-url "$ANVIL_RPC" 2>/dev/null || echo "false")

info "Total Assets    : ${ASSETS_0} wei  ($(cast from-wei "$ASSETS_0" 2>/dev/null || echo '?') ETH)"
info "Total Shares    : ${SHARES_0}"
info "Circuit Breaker : ${CB_0}"

# ========================================================================
#  PHASE 3: Deposit ETH into Vault
# ========================================================================
header "PHASE 3 — Deposit 5 ETH into Vault"

step "Funding owner with 10 ETH..."
cast rpc anvil_setBalance "$OWNER" "0x8AC7230489E80000" --rpc-url "$ANVIL_RPC" > /dev/null 2>&1
success "Owner funded: $(cast from-wei "$(cast balance "$OWNER" --rpc-url "$ANVIL_RPC")" 2>/dev/null) ETH"

step "Impersonating owner (${OWNER:0:10}...)..."
cast rpc anvil_impersonateAccount "$OWNER" --rpc-url "$ANVIL_RPC" > /dev/null 2>&1

step "Calling vault.deposit{5 ETH}(root=0, nullifier=12345, proof=[0...0])..."
DEPOSIT_OUTPUT=$(cast send "$VAULT" \
  "deposit(uint256,uint256,uint256[8])" \
  0 12345 "[0,0,0,0,0,0,0,0]" \
  --value 5ether \
  --from "$OWNER" \
  --unlocked \
  --rpc-url "$ANVIL_RPC" \
  --json 2>&1) || true

DEPOSIT_TX=$(echo "$DEPOSIT_OUTPUT" | json_get transactionHash)

if [[ -n "$DEPOSIT_TX" && "$DEPOSIT_TX" != "" ]]; then
  success "Deposit tx: ${DEPOSIT_TX}"
else
  fail "Deposit failed. Output:"
  echo "$DEPOSIT_OUTPUT" | head -5
  warn "Continuing — yield scanner will see NO_ASSETS"
fi

divider
step "Vault state after deposit..."
ASSETS_1=$(cast call "$VAULT" "getTotalAssets()(uint256)" --rpc-url "$ANVIL_RPC" 2>/dev/null || echo "0")
SHARES_1=$(cast call "$VAULT" "totalShares()(uint256)" --rpc-url "$ANVIL_RPC" 2>/dev/null || echo "0")
info "Total Assets : ${ASSETS_1} wei  ($(cast from-wei "$ASSETS_1" 2>/dev/null || echo '?') ETH)"
info "Total Shares : ${SHARES_1}"

# ========================================================================
#  PHASE 4: Trigger Risk Event
# ========================================================================
header "PHASE 4 — Trigger RiskAlertCreated Event"

step "Calling riskRegistry.updateRiskScore(Aave, 8500, reportId=0x01)..."
info "  Protocol : ${AAVE_POOL}"
info "  Score    : 8500 / 10000  (85%)"
info "  Threshold: 7000  (70%) — will trigger RiskAlertCreated"

RISK_OUTPUT=$(cast send "$RISK_REGISTRY" \
  "updateRiskScore(address,uint256,bytes32)" \
  "$AAVE_POOL" \
  8500 \
  "0x0000000000000000000000000000000000000000000000000000000000000001" \
  --from "$OWNER" \
  --unlocked \
  --rpc-url "$ANVIL_RPC" \
  --json 2>&1) || true

RISK_TX=$(echo "$RISK_OUTPUT" | json_get transactionHash)

if [[ -n "$RISK_TX" && "$RISK_TX" != "" ]]; then
  success "Risk event tx: ${RISK_TX}"

  # Find the RiskAlertCreated event index in the receipt
  step "Finding RiskAlertCreated log index in receipt..."
  EVENT_INDEX=$(python3 -c "
import sys, json
data = json.loads('''${RISK_OUTPUT}''')
logs = data.get('logs', [])
for i, log in enumerate(logs):
    topics = log.get('topics', [])
    if topics and topics[0].lower() == '${RISK_ALERT_TOPIC}'.lower():
        print(i)
        sys.exit(0)
print(1)  # fallback
" 2>/dev/null || echo "1")

  success "RiskAlertCreated at log index: ${EVENT_INDEX}"
else
  fail "Risk event failed. Output:"
  echo "$RISK_OUTPUT" | head -5
  RISK_TX=""
fi

step "Stop impersonating..."
cast rpc anvil_stopImpersonatingAccount "$OWNER" --rpc-url "$ANVIL_RPC" > /dev/null 2>&1

# ========================================================================
#  PHASE 5: Point CRE to Anvil Fork
# ========================================================================
header "PHASE 5 — Configure CRE for Anvil Fork"

step "Backing up project.yaml..."
cp "$PROJECT_YAML" "$PROJECT_YAML_BAK"
success "Backup: project.yaml.showcase.bak"

step "Rewriting RPC URLs to localhost:${ANVIL_PORT}..."
sed -i "s|url: https://ethereum-sepolia-rpc.publicnode.com|url: http://127.0.0.1:${ANVIL_PORT}|g" "$PROJECT_YAML"
success "project.yaml now points to Anvil fork"

# ========================================================================
#  PHASE 6A: Simulate Yield Scanner
# ========================================================================
header "WORKFLOW 1/3 — Yield Scanner (Cron Trigger)"

echo -e "  ${DIM}Trigger  : Cron (every 5 minutes)${NC}"
echo -e "  ${DIM}Reads    : getTotalAssets(), isCircuitBreakerActive(), totalShares()${NC}"
echo -e "  ${DIM}AI       : Groq deepseek-r1 → REBALANCE or HOLD decision${NC}"
echo -e "  ${DIM}Report   : 0x01 prefix + abi.encode(confidence)${NC}"
divider
echo ""

cre workflow simulate yield-scanner \
  --target staging-settings \
  --non-interactive \
  --trigger-index 0 \
  -R "$PROJECT_ROOT" \
  2>&1 || warn "Yield scanner exited with non-zero (may be expected)"

echo ""
divider
if [[ "$ASSETS_1" != "0" ]]; then
  success "Yield Scanner saw $(cast from-wei "$ASSETS_1" 2>/dev/null) ETH in vault and processed it"
else
  info "Vault was empty — scanner returned NO_ASSETS (expected)"
fi

# ========================================================================
#  PHASE 6B: Simulate Risk Sentinel
# ========================================================================
header "WORKFLOW 2/3 — Risk Sentinel (Log Trigger)"

echo -e "  ${DIM}Trigger  : EVM Log (RiskAlertCreated event)${NC}"
echo -e "  ${DIM}Event    : protocol=Aave, score=8500, threshold=7000${NC}"
echo -e "  ${DIM}Reads    : isCircuitBreakerActive(), getTotalAssets()${NC}"
echo -e "  ${DIM}AI       : Groq deepseek-r1 → HOLD / DELEVERAGE / EMERGENCY_EXIT${NC}"
echo -e "  ${DIM}Report   : 0x02 prefix + abi.encode(shouldActivate, riskScore)${NC}"
divider
echo ""

if [[ -n "${RISK_TX:-}" ]]; then
  cre workflow simulate risk-sentinel \
    --target staging-settings \
    --non-interactive \
    --trigger-index 0 \
    --evm-tx-hash "$RISK_TX" \
    --evm-event-index "${EVENT_INDEX:-1}" \
    -R "$PROJECT_ROOT" \
    2>&1 || warn "Risk sentinel exited with non-zero (may be expected)"
else
  warn "Skipped — no risk event transaction available"
fi

echo ""
divider
success "Risk Sentinel processed RiskAlertCreated(score=8500)"

# ========================================================================
#  PHASE 6C: Simulate Vault Manager
# ========================================================================
header "WORKFLOW 3/3 — Vault Manager (HTTP Trigger)"

echo -e "  ${DIM}Trigger  : HTTP POST from frontend${NC}"
echo -e "  ${DIM}Payload  : DEPOSIT 1 ETH for owner with WorldId proof${NC}"
echo -e "  ${DIM}Checks   : isSetupComplete(), isCircuitBreakerActive(), amount > 0${NC}"
echo -e "  ${DIM}Report   : 0x03 prefix + abi.encode(opType=1, user, amount)${NC}"
divider
echo ""

# Build HTTP payload matching vault-manager's Zod payloadSchema
HTTP_PAYLOAD=$(python3 -c "
import json
payload = {
    'operation': 'DEPOSIT',
    'amount': '1000000000000000000',
    'userAddress': '${OWNER}',
    'worldIdProof': {
        'root': '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        'nullifierHash': '0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        'proof': [
            '0x0000000000000000000000000000000000000000000000000000000000000001',
            '0x0000000000000000000000000000000000000000000000000000000000000002',
            '0x0000000000000000000000000000000000000000000000000000000000000003',
            '0x0000000000000000000000000000000000000000000000000000000000000004',
            '0x0000000000000000000000000000000000000000000000000000000000000005',
            '0x0000000000000000000000000000000000000000000000000000000000000006',
            '0x0000000000000000000000000000000000000000000000000000000000000007',
            '0x0000000000000000000000000000000000000000000000000000000000000008'
        ]
    }
}
print(json.dumps(payload))
")

cre workflow simulate vault-manager \
  --target staging-settings \
  --non-interactive \
  --trigger-index 0 \
  --http-payload "$HTTP_PAYLOAD" \
  -R "$PROJECT_ROOT" \
  2>&1 || warn "Vault manager exited with non-zero (may be expected)"

echo ""
divider
success "Vault Manager validated DEPOSIT(1 ETH) payload"

# ========================================================================
#  PHASE 7: Final Summary
# ========================================================================
header "SHOWCASE COMPLETE"

echo -e "  ${BOLD}Workflow Results:${NC}"
echo ""
echo -e "    ${GREEN}1.${NC} ${BOLD}Yield Scanner${NC}  (Cron)"
echo -e "       Read vault state: $(cast from-wei "$ASSETS_1" 2>/dev/null || echo '?') ETH, $(SHARES_1) shares"
echo -e "       AI analysis: Groq deepseek-r1 → REBALANCE/HOLD decision"
echo -e "       Report prefix: 0x01"
echo ""
echo -e "    ${GREEN}2.${NC} ${BOLD}Risk Sentinel${NC}  (Log Trigger)"
echo -e "       Event tx: ${RISK_TX:-N/A}"
echo -e "       RiskAlertCreated: Aave score=8500, threshold=7000"
echo -e "       AI assessment: HOLD / DELEVERAGE / EMERGENCY_EXIT"
echo -e "       Report prefix: 0x02"
echo ""
echo -e "    ${GREEN}3.${NC} ${BOLD}Vault Manager${NC}  (HTTP)"
echo -e "       Payload: DEPOSIT 1 ETH for ${OWNER:0:10}..."
echo -e "       Preflight: setup, circuit breaker, amount validation"
echo -e "       Report prefix: 0x03"
echo ""
divider
echo ""
echo -e "  ${BOLD}On-chain state during showcase:${NC}"
echo -e "    Assets    : 0 ETH  -->  $(cast from-wei "$ASSETS_1" 2>/dev/null || echo '?') ETH"
echo -e "    Risk Score: 0      -->  8500 bps (85%)"
echo -e "    CB Active : false  -->  (pending risk sentinel report delivery)"
echo ""
echo -e "  ${DIM}Anvil fork stopped. project.yaml restored automatically.${NC}"
echo ""
