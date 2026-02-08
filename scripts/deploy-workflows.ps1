# AEGIS Protocol - Deploy All Workflows to CRE
# Run from project root: .\scripts\deploy-workflows.ps1
# WARNING: Only run after successful simulation and config review

$ErrorActionPreference = "Stop"

Write-Host "=== AEGIS Protocol - Workflow Deployment ===" -ForegroundColor Cyan
Write-Host ""

# Pre-deploy checks
Write-Host "[0/4] Pre-deploy validation..." -ForegroundColor Yellow
bun run scripts/configValidator.ts
if ($LASTEXITCODE -ne 0) {
    Write-Host "Config validation failed - cannot deploy" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Confirm deployment
$confirm = Read-Host "Deploy all 3 workflows to CRE? (y/N)"
if ($confirm -ne "y") {
    Write-Host "Deployment cancelled" -ForegroundColor Yellow
    exit 0
}

# Step 1: Deploy Yield Scanner
Write-Host "[1/3] Deploying Yield Scanner..." -ForegroundColor Yellow
cre workflow deploy yield-scanner --target staging-settings
if ($LASTEXITCODE -ne 0) {
    Write-Host "Yield Scanner deployment failed" -ForegroundColor Red
    exit 1
}
Write-Host "Yield Scanner: DEPLOYED" -ForegroundColor Green
Write-Host ""

# Step 2: Deploy Risk Sentinel
Write-Host "[2/3] Deploying Risk Sentinel..." -ForegroundColor Yellow
cre workflow deploy risk-sentinel --target staging-settings
if ($LASTEXITCODE -ne 0) {
    Write-Host "Risk Sentinel deployment failed" -ForegroundColor Red
    exit 1
}
Write-Host "Risk Sentinel: DEPLOYED" -ForegroundColor Green
Write-Host ""

# Step 3: Deploy Vault Manager
Write-Host "[3/3] Deploying Vault Manager..." -ForegroundColor Yellow
cre workflow deploy vault-manager --target staging-settings
if ($LASTEXITCODE -ne 0) {
    Write-Host "Vault Manager deployment failed" -ForegroundColor Red
    exit 1
}
Write-Host "Vault Manager: DEPLOYED" -ForegroundColor Green
Write-Host ""

Write-Host "=== All 3 workflows deployed successfully ===" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Verify workflows in CRE dashboard"
Write-Host "  2. Update AegisVault workflowToPrefix bindings with deployed workflow IDs"
Write-Host "  3. Test end-to-end with a deposit transaction"
