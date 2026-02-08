# AEGIS Protocol - Test HTTP Trigger (Vault Manager)
# Run from project root: .\scripts\test-http-trigger.ps1

$ErrorActionPreference = "Stop"

Write-Host "=== Testing Vault Manager HTTP Trigger ===" -ForegroundColor Cyan
Write-Host ""

# Test deposit payload
$depositPayload = @{
    operation = "DEPOSIT"
    amount = "1000000000000000000"
    userAddress = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
    worldIdProof = @{
        root = "12345"
        nullifierHash = "111111"
        proof = @("0", "0", "0", "0", "0", "0", "0", "0")
    }
} | ConvertTo-Json -Depth 3

Write-Host "Sending DEPOSIT request..." -ForegroundColor Yellow
Write-Host "Payload: $depositPayload" -ForegroundColor Gray
Write-Host ""

# Simulate the workflow with HTTP trigger
cre workflow simulate vault-manager --target staging-settings --input "$depositPayload"

Write-Host ""
Write-Host "=== HTTP Trigger Test Complete ===" -ForegroundColor Green
