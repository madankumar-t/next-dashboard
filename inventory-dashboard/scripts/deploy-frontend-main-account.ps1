# ============================================================
# Deploy Frontend (S3 + CloudFront) - Main Account
# Account : dcli_sharedsvcs2  (975678945875)
# ============================================================
# Usage:
#   .\deploy-frontend-main-account.ps1 -ApiUrl https://xxxx.execute-api.us-east-1.amazonaws.com/dev
#   .\deploy-frontend-main-account.ps1 -ApiUrl <url> -SkipBuild
# ============================================================

param(
    [string] $Profile            = "dcli_sharedsvcs2",
    [string] $Region             = "us-east-1",
    [string] $BucketName         = "aws-inventory-dashboard-frontend-975678945875",
    [string] $FrontendStackName  = "aws-inventory-dashboard-frontend",
    # API Gateway URL from the backend SAM stack output (required)
    [string] $ApiUrl             = "",
    # Existing Cognito (shared services account)
    [string] $CognitoUserPoolId  = "us-east-1_CiQtVfFnM",
    [string] $CognitoClientId    = "39v2nj1ueoajpeqfrckpthd0go",
    [string] $CognitoRegion      = "us-east-1",
    [string] $CognitoDomain      = "",          # e.g. my-domain (without .auth.region.amazoncognito.com)
    # Skip npm build if already built
    [switch] $SkipBuild,
    [switch] $SkipInfrastructure
)

$ErrorActionPreference = "Stop"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " AWS Inventory Dashboard - Frontend Deployment" -ForegroundColor Cyan
Write-Host " Main Account : dcli_sharedsvcs2 (975678945875)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ---- verify credentials ----
Write-Host "Verifying AWS credentials (profile: $Profile)..." -ForegroundColor Yellow
$callerJson = aws sts get-caller-identity --profile $Profile --region $Region --output json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Cannot reach AWS with profile '$Profile'. Check credentials." -ForegroundColor Red
    exit 1
}
$caller = $callerJson | ConvertFrom-Json
Write-Host "  Account: $($caller.Account) | ARN: $($caller.Arn)" -ForegroundColor Green

if ($caller.Account -ne "975678945875") {
    Write-Host "WARNING: Current account ($($caller.Account)) != expected main account (975678945875)." -ForegroundColor Red
    $resp = Read-Host "Continue? (yes/no)"
    if ($resp -ne "yes") { exit 0 }
}
Write-Host ""

# ---- resolve paths ----
$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$frontendDir = Join-Path (Split-Path -Parent $scriptDir) "frontend"

if (-not (Test-Path $frontendDir)) {
    Write-Host "ERROR: frontend/ not found at $frontendDir" -ForegroundColor Red
    exit 1
}

# ---- auto-detect API URL from SAM stack outputs if not provided ----
if ([string]::IsNullOrEmpty($ApiUrl)) {
    Write-Host "ApiUrl not provided - attempting to detect from CloudFormation stack 'inventory-dashboard'..." -ForegroundColor Yellow
    $ApiUrl = aws cloudformation describe-stacks `
        --stack-name  "inventory-dashboard" `
        --profile     $Profile `
        --region      $Region `
        --query       "Stacks[0].Outputs[?OutputKey=='ApiUrl' || OutputKey=='ApiEndpoint' || OutputKey=='InventoryApiUrl'].OutputValue | [0]" `
        --output      text 2>&1
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($ApiUrl) -or $ApiUrl -eq "None") {
        Write-Host "WARNING: Could not auto-detect API URL. You can set it manually in .env.local later." -ForegroundColor Yellow
        $ApiUrl = ""
    } else {
        Write-Host "  Detected API URL: $ApiUrl" -ForegroundColor Green
    }
}
Write-Host ""

# ---- write .env.local ----
Push-Location $frontendDir

Write-Host "Step 1 - Writing .env.local..." -ForegroundColor Yellow
$envContent = @"
NEXT_PUBLIC_API_URL=$ApiUrl
NEXT_PUBLIC_COGNITO_USER_POOL_ID=$CognitoUserPoolId
NEXT_PUBLIC_COGNITO_CLIENT_ID=$CognitoClientId
NEXT_PUBLIC_COGNITO_REGION=$CognitoRegion
NEXT_PUBLIC_COGNITO_DOMAIN=$CognitoDomain
"@
$envContent | Set-Content ".env.local" -Encoding UTF8
Write-Host "  .env.local written." -ForegroundColor Green
Write-Host ""

# ---- deploy S3/CloudFront infrastructure ----
if (-not $SkipInfrastructure) {
    Write-Host "Step 2 - Deploying S3 + CloudFront infrastructure (CloudFormation)..." -ForegroundColor Yellow
    $infraTemplate = Join-Path $frontendDir "frontend-infrastructure.yaml"
    if (Test-Path $infraTemplate) {
        $cfnParams = @(
            "ParameterKey=S3BucketName,ParameterValue=$BucketName"
        )

        $existingFrontendStack = aws cloudformation describe-stacks `
            --stack-name $FrontendStackName `
            --profile    $Profile `
            --region     $Region `
            --output     json 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Updating existing frontend stack..." -ForegroundColor Yellow
            aws cloudformation update-stack `
                --stack-name   $FrontendStackName `
                --template-body "file://$infraTemplate" `
                --parameters   $cfnParams `
                --capabilities CAPABILITY_IAM `
                --profile      $Profile `
                --region       $Region
            if ($LASTEXITCODE -eq 0) {
                aws cloudformation wait stack-update-complete --stack-name $FrontendStackName --profile $Profile --region $Region
            } else {
                Write-Host "  Stack may already be up-to-date." -ForegroundColor Yellow
            }
        } else {
            aws cloudformation create-stack `
                --stack-name   $FrontendStackName `
                --template-body "file://$infraTemplate" `
                --parameters   $cfnParams `
                --capabilities CAPABILITY_IAM `
                --profile      $Profile `
                --region       $Region
            if ($LASTEXITCODE -ne 0) {
                Write-Host "ERROR: Frontend infrastructure stack creation failed." -ForegroundColor Red
                Pop-Location; exit 1
            }
            aws cloudformation wait stack-create-complete --stack-name $FrontendStackName --profile $Profile --region $Region
        }
        Write-Host "  Infrastructure stack ready." -ForegroundColor Green

        # get CloudFront distribution ID from outputs
        $distributionId = aws cloudformation describe-stacks `
            --stack-name $FrontendStackName `
            --profile    $Profile `
            --region     $Region `
            --query      "Stacks[0].Outputs[?OutputKey=='DistributionId' || OutputKey=='CloudFrontDistributionId'].OutputValue | [0]" `
            --output     text 2>&1
        if ($distributionId -and $distributionId -ne "None") {
            Write-Host "  CloudFront Distribution ID: $distributionId" -ForegroundColor Green
        }
    } else {
        Write-Host "  WARNING: frontend-infrastructure.yaml not found, skipping CloudFormation step." -ForegroundColor Yellow
    }
}
Write-Host ""

# ---- build ----
if (-not $SkipBuild) {
    Write-Host "Step 3 - Installing npm dependencies..." -ForegroundColor Yellow
    npm install
    if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: npm install failed." -ForegroundColor Red; Pop-Location; exit 1 }

    Write-Host "Step 4 - Building Next.js static export..." -ForegroundColor Yellow
    $env:NEXT_EXPORT = "true"
    npm run build:static
    if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: Build failed." -ForegroundColor Red; Pop-Location; exit 1 }
    Write-Host "  Build successful." -ForegroundColor Green
} else {
    Write-Host "Step 3/4 - Skipping build (SkipBuild flag set)." -ForegroundColor Yellow
}
Write-Host ""

# ---- S3 sync ----
if (-not (Test-Path "out")) {
    Write-Host "ERROR: 'out/' directory not found. Run build first or remove -SkipBuild." -ForegroundColor Red
    Pop-Location; exit 1
}

Write-Host "Step 5 - Syncing static files to s3://$BucketName ..." -ForegroundColor Yellow
aws s3 sync out/ "s3://$BucketName" `
    --delete `
    --profile $Profile `
    --region  $Region

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: S3 sync failed." -ForegroundColor Red
    Pop-Location; exit 1
}
Write-Host "  S3 sync complete." -ForegroundColor Green
Write-Host ""

# ---- CloudFront invalidation ----
if ($distributionId -and $distributionId -ne "None") {
    Write-Host "Step 6 - Invalidating CloudFront cache..." -ForegroundColor Yellow
    aws cloudfront create-invalidation `
        --distribution-id $distributionId `
        --paths           "/*" `
        --profile         $Profile
    Write-Host "  Invalidation requested." -ForegroundColor Green
} else {
    Write-Host "Step 6 - Skipping CloudFront invalidation (no distribution ID found)." -ForegroundColor Yellow
}

Pop-Location

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " Frontend deployment complete!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Frontend stack outputs:" -ForegroundColor Cyan
aws cloudformation describe-stacks `
    --stack-name $FrontendStackName `
    --profile    $Profile `
    --region     $Region `
    --query      "Stacks[0].Outputs" `
    --output     table 2>$null
