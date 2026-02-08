# AEGIS Protocol - Simulate All Workflows
# Run from project root: .\scripts\simulate-all.ps1

$ErrorActionPreference = "Stop"

Write-Host "=== AEGIS Protocol - Workflow Simulation ===" -ForegroundColor Cyan
Write-Host ""

# Step 1: Validate configs
Write-Host "[1/4] Validating config consistency..." -ForegroundColor Yellow
bun run scripts/configValidator.ts
if ($LASTEXITCODE -ne 0) {
    Write-Host "Config validation failed - fix errors before simulating" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Step 2: Simulate Yield Scanner (Cron Trigger)
Write-Host "[2/4] Simulating Yield Scanner..." -ForegroundColor Yellow
cre workflow simulate yield-scanner --target staging-settings
if ($LASTEXITCODE -ne 0) {
    Write-Host "Yield Scanner simulation failed" -ForegroundColor Red
    exit 1
}
Write-Host "Yield Scanner: OK" -ForegroundColor Green
Write-Host ""

# Step 3: Simulate Risk Sentinel (Log Trigger)
Write-Host "[3/4] Simulating Risk Sentinel..." -ForegroundColor Yellow
cre workflow simulate risk-sentinel --target staging-settings
if ($LASTEXITCODE -ne 0) {
    Write-Host "Risk Sentinel simulation failed" -ForegroundColor Red
    exit 1
}
Write-Host "Risk Sentinel: OK" -ForegroundColor Green
Write-Host ""

# Step 4: Simulate Vault Manager (HTTP Trigger)
Write-Host "[4/4] Simulating Vault Manager..." -ForegroundColor Yellow
cre workflow simulate vault-manager --target staging-settings
if ($LASTEXITCODE -ne 0) {
    Write-Host "Vault Manager simulation failed" -ForegroundColor Red
    exit 1
}
Write-Host "Vault Manager: OK" -ForegroundColor Green
Write-Host ""

Write-Host "=== All 3 workflows simulated successfully ===" -ForegroundColor Green
