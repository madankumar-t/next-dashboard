# PowerShell script to create cross-account role with trust policy and permissions
# Usage: .\create-cross-account-role-complete.ps1 -MemberAccountId <ID> -MainAccountId <ID> [-LambdaRoleName <NAME>] [-ExternalId <ID>] [-RoleName <NAME>]

param(
    [Parameter(Mandatory=$true)]
    [string]$MemberAccountId,
    
    [Parameter(Mandatory=$true)]
    [string]$MainAccountId,
    
    [Parameter(Mandatory=$false)]
    [string]$LambdaRoleName = "",
    
    [Parameter(Mandatory=$false)]
    [string]$ExternalId = "",
    
    [Parameter(Mandatory=$false)]
    [string]$RoleName = "InventoryReadRole"
)

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PolicyFile = Join-Path $ScriptDir "policies\inventory-read-policy.json"

if (-not (Test-Path $PolicyFile)) {
    Write-Error "Policy file not found: $PolicyFile"
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Cross-Account Role Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Member Account ID: $MemberAccountId"
Write-Host "Main Account ID: $MainAccountId"
Write-Host "Role Name: $RoleName"
if (-not [string]::IsNullOrEmpty($LambdaRoleName)) {
    Write-Host "Lambda Role: $LambdaRoleName"
} else {
    Write-Host "Lambda Role: (using account root)"
}
if (-not [string]::IsNullOrEmpty($ExternalId)) {
    Write-Host "External ID: *** (hidden)"
} else {
    Write-Host "External ID: (not using)"
}
Write-Host ""

# Step 1: Create trust policy
Write-Host "Step 1: Creating trust policy..." -ForegroundColor Yellow

$PrincipalArn = if (-not [string]::IsNullOrEmpty($LambdaRoleName)) {
    "arn:aws:iam::${MainAccountId}:role/${LambdaRoleName}"
} else {
    "arn:aws:iam::${MainAccountId}:root"
}

$TrustPolicy = @{
    Version = "2012-10-17"
    Statement = @(
        @{
            Effect = "Allow"
            Principal = @{
                AWS = $PrincipalArn
            }
            Action = "sts:AssumeRole"
        }
    )
}

if (-not [string]::IsNullOrEmpty($ExternalId)) {
    $TrustPolicy.Statement[0].Condition = @{
        StringEquals = @{
            "sts:ExternalId" = $ExternalId
        }
    }
}

$TrustPolicyJson = $TrustPolicy | ConvertTo-Json -Depth 10

# Step 2: Create role
Write-Host "Step 2: Creating IAM role..." -ForegroundColor Yellow

try {
    $ExistingRole = Get-IAMRole -RoleName $RoleName -ErrorAction Stop
    Write-Host "Role already exists. Updating trust policy..." -ForegroundColor Yellow
    Update-IAMAssumeRolePolicy -RoleName $RoleName -PolicyDocument $TrustPolicyJson
    Write-Host "✓ Trust policy updated" -ForegroundColor Green
} catch {
    if ($_.Exception.Message -like "*does not exist*") {
        New-IAMRole -RoleName $RoleName -AssumeRolePolicyDocument $TrustPolicyJson -Description "Allows AWS Inventory Dashboard to read resources in this account"
        Write-Host "✓ Role created" -ForegroundColor Green
    } else {
        Write-Error "Failed to create/update role: $($_.Exception.Message)"
        exit 1
    }
}

# Step 3: Attach permissions policy
Write-Host "Step 3: Attaching permissions policy..." -ForegroundColor Yellow
$PolicyDocument = Get-Content -Path $PolicyFile -Raw
Write-IAMRolePolicy -RoleName $RoleName -PolicyName "InventoryReadPolicy" -PolicyDocument $PolicyDocument
Write-Host "✓ Permissions policy attached" -ForegroundColor Green

# Step 4: Get role ARN
$RoleArn = (Get-IAMRole -RoleName $RoleName).Arn

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "✓ Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Role ARN: $RoleArn"
Write-Host ""
Write-Host "Next steps:"
Write-Host "1. Verify the role in AWS Console: https://console.aws.amazon.com/iam/home#/roles/${RoleName}"
Write-Host "2. Add this account to INVENTORY_ACCOUNTS environment variable (if not using Organizations)"
Write-Host "3. Test role assumption from main account"
Write-Host ""

