# ============================================================
# MASTER DEPLOYMENT SCRIPT
# AWS Inventory Dashboard - Full Stack
#
# Main account : dcli_sharedsvcs2  (975678945875)
# Client accounts:
#   dcli_sandbox1   529088296711
#   dcli_sandbox2   687360398174
#
# Runs all three deployment steps in order:
#   1. Backend  (SAM Lambda + API Gateway) in main account
#   2. Member   (IAM InventoryReadRole)    in each client account
#   3. Frontend (S3 + CloudFront)          in main account
# ============================================================
# Usage:
#   .\deploy-all.ps1                          # interactive (confirms each step)
#   .\deploy-all.ps1 -SkipConfirmation        # fully automated
#   .\deploy-all.ps1 -Steps Backend,Member    # run only specific steps
#   .\deploy-all.ps1 -Steps Frontend -ApiUrl https://xxx.execute-api...amazonaws.com/dev
# ============================================================

param(
    # Which steps to run (Backend | Member | Frontend)
    [ValidateSet("Backend","Member","Frontend")]
    [string[]] $Steps = @("Backend","Member","Frontend"),

    # ---- shared ----
    [string] $Region          = "us-east-1",
    [string] $Environment     = "dev",

    # ---- main account ----
    [string] $MainProfile     = "dcli_sharedsvcs2",
    [string] $MainAccountId   = "975678945875",

    # ---- backend ----
    [string] $BackendStack    = "inventory-dashboard",
    [string] $InventoryRoleName = "InventoryReadRole",
    [string] $InventoryAccounts = "529088296711:dcli_sandbox1,687360398174:dcli_sandbox2",
    [string] $CognitoUserPoolId = "us-east-1_CiQtVfFnM",
    [string] $CognitoClientId   = "39v2nj1ueoajpeqfrckpthd0go",
    [string] $CognitoRegion     = "us-east-1",
    [string] $ExternalId        = "",

    # ---- frontend ----
    [string] $BucketName         = "aws-inventory-dashboard-frontend-975678945875",
    [string] $FrontendStack      = "aws-inventory-dashboard-frontend",
    # Auto-detected from SAM outputs if not provided
    [string] $ApiUrl             = "",
    [string] $CognitoDomain      = "",

    # ---- flags ----
    [switch] $SkipConfirmation,
    [switch] $SkipFrontendBuild
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Banner ([string]$Text, [string]$Color = "Cyan") {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor $Color
    Write-Host "  $Text" -ForegroundColor $Color
    Write-Host "============================================================" -ForegroundColor $Color
    Write-Host ""
}

function Invoke-Step ([string]$Script, [string[]]$ScriptArgs) {
    $fullPath = Join-Path $scriptDir $Script
    if (-not (Test-Path $fullPath)) {
        Write-Host "ERROR: Script not found: $fullPath" -ForegroundColor Red
        exit 1
    }
    Write-Host "Running: $Script" -ForegroundColor DarkGray
    & $fullPath @ScriptArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: $Script failed (exit code $LASTEXITCODE)." -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

Write-Banner "AWS Inventory Dashboard - Master Deployment" "Cyan"
Write-Host "  Main account : $MainProfile ($MainAccountId)"  -ForegroundColor Yellow
Write-Host "  Client accts : dcli_sandbox1 (529088296711)"   -ForegroundColor Yellow
Write-Host "                 dcli_sandbox2 (687360398174)"   -ForegroundColor Yellow
Write-Host "  Region       : $Region"                         -ForegroundColor Yellow
Write-Host "  Environment  : $Environment"                    -ForegroundColor Yellow
Write-Host "  Steps        : $($Steps -join ' -> ')"          -ForegroundColor Yellow
Write-Host ""

if (-not $SkipConfirmation) {
    $resp = Read-Host "Proceed with deployment? (yes/no)"
    if ($resp -ne "yes") { Write-Host "Aborted." -ForegroundColor Yellow; exit 0 }
}

# ================================================================
# STEP 1 - BACKEND
# ================================================================
if ($Steps -contains "Backend") {
    Write-Banner "STEP 1 / 3 - Backend (SAM)" "Yellow"

    $backendArgs = @(
        "-Profile",              $MainProfile,
        "-Region",               $Region,
        "-Environment",          $Environment,
        "-StackName",            $BackendStack,
        "-InventoryRoleName",    $InventoryRoleName,
        "-InventoryAccounts",    $InventoryAccounts,
        "-CognitoUserPoolId",    $CognitoUserPoolId,
        "-CognitoClientId",      $CognitoClientId,
        "-CognitoRegion",        $CognitoRegion,
        "-ExternalId",           $ExternalId
    )
    if ($SkipConfirmation) { $backendArgs += "-SkipConfirmation" }

    Invoke-Step "deploy-backend-main-account.ps1" $backendArgs

    # Auto-detect API URL for use in frontend step
    if ([string]::IsNullOrEmpty($ApiUrl)) {
        Write-Host "Detecting API URL from stack outputs..." -ForegroundColor Cyan
        $detected = aws cloudformation describe-stacks `
            --stack-name  $BackendStack `
            --profile     $MainProfile `
            --region      $Region `
            --query       "Stacks[0].Outputs[?OutputKey=='ApiUrl' || OutputKey=='ApiEndpoint' || OutputKey=='InventoryApiUrl'].OutputValue | [0]" `
            --output      text 2>&1
        if ($detected -and $detected -ne "None") {
            $ApiUrl = $detected
            Write-Host "  API URL: $ApiUrl" -ForegroundColor Green
        }
    }
}

# ================================================================
# STEP 2 - MEMBER ACCOUNT ROLES
# ================================================================
if ($Steps -contains "Member") {
    Write-Banner "STEP 2 / 3 - Member Account Roles" "Yellow"

    $memberArgs = @(
        "-MainAccountId", $MainAccountId,
        "-Region",        $Region,
        "-RoleName",      $InventoryRoleName,
        "-ExternalId",    $ExternalId
    )
    if ($SkipConfirmation) { $memberArgs += "-SkipConfirmation" }

    Invoke-Step "deploy-member-account-roles.ps1" $memberArgs
}

# ================================================================
# STEP 3 - FRONTEND
# ================================================================
if ($Steps -contains "Frontend") {
    Write-Banner "STEP 3 / 3 - Frontend (S3 + CloudFront)" "Yellow"

    $frontendArgs = @(
        "-Profile",           $MainProfile,
        "-Region",            $Region,
        "-BucketName",        $BucketName,
        "-FrontendStackName", $FrontendStack,
        "-ApiUrl",            $ApiUrl,
        "-CognitoUserPoolId", $CognitoUserPoolId,
        "-CognitoClientId",   $CognitoClientId,
        "-CognitoRegion",     $CognitoRegion,
        "-CognitoDomain",     $CognitoDomain
    )
    if ($SkipFrontendBuild) { $frontendArgs += "-SkipBuild" }

    Invoke-Step "deploy-frontend-main-account.ps1" $frontendArgs
}

# ================================================================
# DONE
# ================================================================
Write-Banner "All requested deployment steps completed successfully!" "Green"
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Backend stack  : $BackendStack   (profile: $MainProfile)" -ForegroundColor White
Write-Host "  Member roles   : InventoryReadRole in dcli_sandbox1 + dcli_sandbox2" -ForegroundColor White
Write-Host "  Frontend stack : $FrontendStack  (profile: $MainProfile)" -ForegroundColor White
Write-Host ""
Write-Host "To verify, open the CloudFront URL from the frontend stack outputs." -ForegroundColor Cyan
