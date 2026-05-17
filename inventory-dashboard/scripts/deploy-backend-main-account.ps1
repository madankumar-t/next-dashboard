# ============================================================
# Deploy Backend (SAM) - Main Account
# Account : dcli_sharedsvcs2  (975678945875)
# ============================================================
# Usage:
#   .\deploy-backend-main-account.ps1
#   .\deploy-backend-main-account.ps1 -Environment prod
#   .\deploy-backend-main-account.ps1 -SkipConfirmation
# ============================================================

param(
    [string]$Environment          = "dev",
    [string]$Profile              = "dcli_sharedsvcs2",
    [string]$Region               = "us-east-1",
    [string]$StackName            = "inventory-dashboard",
    [string]$InventoryRoleName    = "InventoryReadRole",
    # Comma-separated list of client accounts  accountId:Name,...
    [string]$InventoryAccounts    = "529088296711:dcli_sandbox1,687360398174:dcli_sandbox2",
    # Existing Cognito values (already deployed in this account)
    [string]$CognitoUserPoolId    = "us-east-1_CiQtVfFnM",
    [string]$CognitoClientId      = "39v2nj1ueoajpeqfrckpthd0go",
    [string]$CognitoRegion        = "us-east-1",
    [string]$ExternalId           = "",
    [switch]$SkipConfirmation
)

$ErrorActionPreference = "Stop"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " AWS Inventory Dashboard - Backend Deployment" -ForegroundColor Cyan
Write-Host " Main Account : dcli_sharedsvcs2 (975678945875)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Profile    : $Profile"    -ForegroundColor Yellow
Write-Host "  Region     : $Region"     -ForegroundColor Yellow
Write-Host "  Stack      : $StackName"  -ForegroundColor Yellow
Write-Host "  Environment: $Environment" -ForegroundColor Yellow
Write-Host "  Accounts   : $InventoryAccounts" -ForegroundColor Yellow
Write-Host ""

# ---- pre-flight: verify caller identity ----
Write-Host "Verifying AWS credentials..." -ForegroundColor Cyan
$callerJson = aws sts get-caller-identity --profile $Profile --region $Region --output json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Cannot reach AWS with profile '$Profile'. Check credentials." -ForegroundColor Red
    exit 1
}
$caller = $callerJson | ConvertFrom-Json
Write-Host "  Account  : $($caller.Account)"  -ForegroundColor Green
Write-Host "  UserId   : $($caller.UserId)"   -ForegroundColor Green
Write-Host "  ARN      : $($caller.Arn)"      -ForegroundColor Green

if ($caller.Account -ne "975678945875") {
    Write-Host ""
    Write-Host "WARNING: Current account ($($caller.Account)) does not match expected main account (975678945875)." -ForegroundColor Red
    if (-not $SkipConfirmation) {
        $resp = Read-Host "Continue anyway? (yes/no)"
        if ($resp -ne "yes") { Write-Host "Aborted." -ForegroundColor Yellow; exit 0 }
    }
}
Write-Host ""

# ---- move into backend folder ----
$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendDir  = Join-Path (Split-Path -Parent $scriptDir) "backend"

if (-not (Test-Path $backendDir)) {
    Write-Host "ERROR: backend/ folder not found at $backendDir" -ForegroundColor Red
    exit 1
}

Push-Location $backendDir
Write-Host "Working directory: $backendDir" -ForegroundColor Cyan
Write-Host ""

# ---- sam build ----
Write-Host "Step 1 of 2 - Building SAM application..." -ForegroundColor Yellow
sam build --profile $Profile --region $Region
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: sam build failed." -ForegroundColor Red
    Pop-Location; exit 1
}
Write-Host "Build successful." -ForegroundColor Green
Write-Host ""

# ---- sam deploy ----
Write-Host "Step 2 of 2 - Deploying to AWS (profile: $Profile)..." -ForegroundColor Yellow

$paramOverrides = @(
    "Environment=$Environment",
    "ExternalId=$ExternalId",
    "InventoryRoleName=$InventoryRoleName",
    "InventoryAccounts=$InventoryAccounts",
    "ExistingCognitoUserPoolId=$CognitoUserPoolId",
    "ExistingCognitoClientId=$CognitoClientId",
    "CognitoRegion=$CognitoRegion"
) -join " "

$confirmFlag = if ($SkipConfirmation) { "--no-confirm-changeset" } else { "--confirm-changeset" }

sam deploy `
    --stack-name         $StackName `
    --profile            $Profile `
    --region             $Region `
    --capabilities       CAPABILITY_IAM `
    --resolve-s3 `
    --s3-prefix          $StackName `
    --parameter-overrides $paramOverrides `
    $confirmFlag `
    --disable-rollback

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: sam deploy failed." -ForegroundColor Red
    Pop-Location; exit 1
}

Pop-Location

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " Backend deployment complete!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

# ---- collect outputs ----
Write-Host "Stack outputs:" -ForegroundColor Cyan
aws cloudformation describe-stacks `
    --stack-name $StackName `
    --profile    $Profile `
    --region     $Region `
    --query      "Stacks[0].Outputs" `
    --output     table

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Note the API Gateway URL from the outputs above."
Write-Host "  2. Run   .\deploy-member-account-roles.ps1   to set up sandbox accounts."
Write-Host "  3. Run   .\deploy-frontend-main-account.ps1  to deploy the frontend."
