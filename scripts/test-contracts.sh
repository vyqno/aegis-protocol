#!/bin/bash
# AEGIS Protocol - Contract Interaction Test Script
# Tests deployed contracts on Sepolia without needing frontend

set -e

# Load environment variables
source .env

# Contract addresses from deployment
VAULT="0x92Bf1f6a56A39F64bfD86e53a4D40c1F35D3965a"
RISK_REGISTRY="0x9CA2221e10F55d5CCae3b6ca2d749A360D9ba82c"
STRATEGY_ROUTER="0xf33C966ef21C783d8f921f2c9Df43bdB20C14855"
WORLD_ID_GATE="0x98cdd8449Fb1022A7015F0332F95778bc85da7F1"

echo "🧪 AEGIS Protocol - Contract Tests"
echo "=================================="
echo ""

# Test 1: Vault State
echo "📊 Test 1: Read Vault State"
echo "----------------------------"
echo -n "Total Assets: "
cast call $VAULT "getTotalAssets()" --rpc-url $SEPOLIA_RPC_URL

echo -n "Total Shares: "
cast call $VAULT "totalShares()" --rpc-url $SEPOLIA_RPC_URL

echo -n "Circuit Breaker Active: "
cast call $VAULT "isCircuitBreakerActive()" --rpc-url $SEPOLIA_RPC_URL

echo -n "Setup Complete: "
cast call $VAULT "isSetupComplete()" --rpc-url $SEPOLIA_RPC_URL

echo -n "Min Deposit: "
cast call $VAULT "minDeposit()" --rpc-url $SEPOLIA_RPC_URL
echo ""

# Test 2: Risk Registry State
echo "🔒 Test 2: Risk Registry State"
echo "-------------------------------"
echo -n "Circuit Breaker Active: "
cast call $RISK_REGISTRY "isCircuitBreakerActive()" --rpc-url $SEPOLIA_RPC_URL

echo -n "Risk Threshold: "
cast call $RISK_REGISTRY "riskThreshold()" --rpc-url $SEPOLIA_RPC_URL

echo -n "Total Alerts: "
cast call $RISK_REGISTRY "totalAlerts()" --rpc-url $SEPOLIA_RPC_URL

# Get Aave V3 risk assessment
AAVE_V3="0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951"
echo "Risk Assessment for Aave V3 ($AAVE_V3):"
cast call $RISK_REGISTRY \
  "getRiskAssessment(address)" \
  $AAVE_V3 \
  --rpc-url $SEPOLIA_RPC_URL
echo ""

# Test 3: Strategy Router State
echo "🎯 Test 3: Strategy Router State"
echo "---------------------------------"
echo -n "Remaining Transfer Budget: "
cast call $STRATEGY_ROUTER \
  "getRemainingTransferBudget()" \
  --rpc-url $SEPOLIA_RPC_URL

# Sepolia chain selector: 16015286601757825753
echo -n "Sepolia Allocation: "
cast call $STRATEGY_ROUTER \
  "getTargetAllocation(uint64)" \
  16015286601757825753 \
  --rpc-url $SEPOLIA_RPC_URL

echo -n "Sepolia Chain Allowed: "
cast call $STRATEGY_ROUTER \
  "isChainAllowed(uint64)" \
  16015286601757825753 \
  --rpc-url $SEPOLIA_RPC_URL
echo ""

# Test 4: Check recent events
echo "📡 Test 4: Recent Events (last 1000 blocks)"
echo "--------------------------------------------"
echo "Deposited events:"
cast logs --from-block -1000 --to-block latest \
  --address $VAULT \
  "event Deposited(address indexed user, uint256 assets, uint256 shares)" \
  --rpc-url $SEPOLIA_RPC_URL || echo "No deposits yet"

echo ""
echo "YieldReportReceived events:"
cast logs --from-block -1000 --to-block latest \
  --address $VAULT \
  "event YieldReportReceived(bytes32 indexed reportKey, bytes data)" \
  --rpc-url $SEPOLIA_RPC_URL || echo "No yield reports yet (CRE workflows not deployed)"

echo ""
echo "✅ All tests completed!"
echo ""
echo "💡 Next Steps:"
echo "  1. Make test deposit: bash scripts/test-deposit.sh"
echo "  2. Start frontend: cd frontend && npm run dev"
echo "  3. Deploy CRE workflows (after Feb 14): cre workflow deploy yield-scanner"
