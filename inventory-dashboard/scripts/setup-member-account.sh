#!/usr/bin/env bash
# Multi-Account Setup - Quick Deploy Script
# Run this in EACH member account (090130567842, 780781249373, 014402785795, 196690901583)

set -euo pipefail

STACK_NAME="${1:-inventory-dashboard-member-role}"

echo "========================================"
echo "AWS Inventory Dashboard - Member Account Role Setup"
echo "========================================"
echo ""

# Configuration
MAIN_ACCOUNT_ID="964201074108"
LAMBDA_ROLE_NAME="inventory-dashboard-RefreshFunctionRole-zoovJCpyuZXf"
ROLE_NAME="InventoryReadRole"

echo "Main Account ID: $MAIN_ACCOUNT_ID"
echo "Lambda Role: $LAMBDA_ROLE_NAME"
echo "Role to Create: $ROLE_NAME"
echo ""

# Get current account ID
echo "Checking current AWS account..."
CURRENT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

echo "Current Account: $CURRENT_ACCOUNT"

if [ "$CURRENT_ACCOUNT" == "$MAIN_ACCOUNT_ID" ]; then
    echo "⚠️  WARNING: You are in the main account. This script should be run in MEMBER accounts only!"
    read -p "Do you want to continue anyway? (yes/no): " response
    if [ "$response" != "yes" ]; then
        echo "Aborted."
        exit 0
    fi
fi

echo ""
echo "Deploying IAM role in account $CURRENT_ACCOUNT..."

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TEMPLATE_PATH="$SCRIPT_DIR/../member-account-role.yaml"

# Deploy CloudFormation stack
aws cloudformation create-stack \
    --stack-name "$STACK_NAME" \
    --template-body "file://$TEMPLATE_PATH" \
    --parameters \
        ParameterKey=MainAccountId,ParameterValue="$MAIN_ACCOUNT_ID" \
        ParameterKey=LambdaExecutionRoleName,ParameterValue="$LAMBDA_ROLE_NAME" \
        ParameterKey=RoleName,ParameterValue="$ROLE_NAME" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region us-east-1

echo ""
echo "Waiting for stack to complete..."
aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME" --region us-east-1

echo ""
echo "✅ SUCCESS! Role created in account $CURRENT_ACCOUNT"
echo ""

# Get role ARN
ROLE_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='RoleArn'].OutputValue" \
    --output text \
    --region us-east-1)

echo "Role ARN: $ROLE_ARN"
echo ""
echo "========================================"
echo "Next Steps:"
echo "1. Repeat this process in other member accounts"
echo "2. After all accounts are configured, test the dashboard"
echo "========================================"
