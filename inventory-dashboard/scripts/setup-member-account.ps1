# Multi-Account Setup - Quick Deploy Script
# Run this in EACH member account (090130567842, 780781249373, 014402785795, 196690901583)

param(
    [Parameter(Mandatory = $true)]
    [string]$StackName = "inventory-dashboard-member-role"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "AWS Inventory Dashboard - Member Account Role Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Configuration
$MainAccountId = "964201074108"
$LambdaRoleName = "inventory-dashboard-RefreshFunctionRole-zoovJCpyuZXf"
$RoleName = "InventoryReadRole"

Write-Host "Main Account ID: $MainAccountId" -ForegroundColor Yellow
Write-Host "Lambda Role: $LambdaRoleName" -ForegroundColor Yellow
Write-Host "Role to Create: $RoleName" -ForegroundColor Yellow
Write-Host ""

# Get current account ID
Write-Host "Checking current AWS account..." -ForegroundColor Cyan
$currentAccount = aws sts get-caller-identity --query Account --output text

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to get current account ID. Check AWS credentials." -ForegroundColor Red
    exit 1
}

Write-Host "Current Account: $currentAccount" -ForegroundColor Green

if ($currentAccount -eq $MainAccountId) {
    Write-Host "WARNING: You are in the main account. This script should be run in MEMBER accounts only!" -ForegroundColor Red
    $response = Read-Host "Do you want to continue anyway? (yes/no)"
    if ($response -ne "yes") {
        Write-Host "Aborted." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ""
Write-Host "Deploying IAM role in account $currentAccount..." -ForegroundColor Cyan

# Deploy CloudFormation stack
aws cloudformation create-stack `
    --stack-name $StackName `
    --template-body file://../member-account-role.yaml `
    --parameters `
    ParameterKey=MainAccountId, ParameterValue=$MainAccountId `
    ParameterKey=LambdaExecutionRoleName, ParameterValue=$LambdaRoleName `
    ParameterKey=RoleName, ParameterValue=$RoleName `
    --capabilities CAPABILITY_NAMED_IAM `
    --region us-east-1

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERROR: Stack creation failed. The stack may already exist." -ForegroundColor Red
    Write-Host "To update an existing stack, run:" -ForegroundColor Yellow
    Write-Host "  aws cloudformation update-stack --stack-name $StackName --template-body file://../member-account-role.yaml --parameters ParameterKey=MainAccountId,ParameterValue=$MainAccountId ParameterKey=LambdaExecutionRoleName,ParameterValue=$LambdaRoleName ParameterKey=RoleName,ParameterValue=$RoleName --capabilities CAPABILITY_NAMED_IAM --region us-east-1" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "Waiting for stack to complete..." -ForegroundColor Yellow
aws cloudformation wait stack-create-complete --stack-name $StackName --region us-east-1

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Stack creation failed or timed out" -ForegroundColor Red
    Write-Host "Check the CloudFormation console for details" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "✅ SUCCESS! Role created in account $currentAccount" -ForegroundColor Green
Write-Host ""

# Get role ARN
$roleArn = aws cloudformation describe-stacks `
    --stack-name $StackName `
    --query "Stacks[0].Outputs[?OutputKey=='RoleArn'].OutputValue" `
    --output text `
    --region us-east-1

Write-Host "Role ARN: $roleArn" -ForegroundColor Green
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "1. Repeat this process in other member accounts" -ForegroundColor White
Write-Host "2. After all accounts are configured, test the dashboard" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
