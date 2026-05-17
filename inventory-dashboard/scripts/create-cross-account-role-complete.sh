#!/bin/bash

# Complete script to create cross-account role with trust policy and permissions
# Usage: ./create-cross-account-role-complete.sh <MEMBER_ACCOUNT_ID> <MAIN_ACCOUNT_ID> [LAMBDA_ROLE_NAME] [EXTERNAL_ID] [ROLE_NAME]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
MEMBER_ACCOUNT_ID="${1}"
MAIN_ACCOUNT_ID="${2}"
LAMBDA_ROLE_NAME="${3}"
EXTERNAL_ID="${4}"
ROLE_NAME="${5:-InventoryReadRole}"

# Validate inputs
if [ -z "$MEMBER_ACCOUNT_ID" ] || [ -z "$MAIN_ACCOUNT_ID" ]; then
    echo -e "${RED}Error: Member account ID and Main account ID are required${NC}"
    echo "Usage: $0 <MEMBER_ACCOUNT_ID> <MAIN_ACCOUNT_ID> [LAMBDA_ROLE_NAME] [EXTERNAL_ID] [ROLE_NAME]"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Cross-Account Role Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo "Member Account ID: $MEMBER_ACCOUNT_ID"
echo "Main Account ID: $MAIN_ACCOUNT_ID"
echo "Role Name: $ROLE_NAME"
[ -n "$LAMBDA_ROLE_NAME" ] && echo "Lambda Role: $LAMBDA_ROLE_NAME" || echo "Lambda Role: (using account root)"
[ -n "$EXTERNAL_ID" ] && echo "External ID: *** (hidden)" || echo "External ID: (not using)"
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_FILE="${SCRIPT_DIR}/policies/inventory-read-policy.json"

if [ ! -f "$POLICY_FILE" ]; then
    echo -e "${RED}Error: Policy file not found: $POLICY_FILE${NC}"
    exit 1
fi

# Step 1: Create trust policy
echo -e "${YELLOW}Step 1: Creating trust policy...${NC}"
TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "$([ -n "$LAMBDA_ROLE_NAME" ] && echo "arn:aws:iam::${MAIN_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}" || echo "arn:aws:iam::${MAIN_ACCOUNT_ID}:root")"
      },
      "Action": "sts:AssumeRole"$([ -n "$EXTERNAL_ID" ] && echo ",
      \"Condition\": {
        \"StringEquals\": {
          \"sts:ExternalId\": \"${EXTERNAL_ID}\"
        }
      }" || echo "")
    }
  ]
}
EOF
)

# Step 2: Create role
echo -e "${YELLOW}Step 2: Creating IAM role...${NC}"
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
    echo -e "${YELLOW}Role already exists. Updating trust policy...${NC}"
    echo "$TRUST_POLICY" > /tmp/trust-policy.json
    aws iam update-assume-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-document file:///tmp/trust-policy.json
    rm /tmp/trust-policy.json
    echo -e "${GREEN}✓ Trust policy updated${NC}"
else
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document "$TRUST_POLICY" \
        --description "Allows AWS Inventory Dashboard to read resources in this account"
    echo -e "${GREEN}✓ Role created${NC}"
fi

# Step 3: Attach permissions policy
echo -e "${YELLOW}Step 3: Attaching permissions policy...${NC}"
aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name InventoryReadPolicy \
    --policy-document file://"$POLICY_FILE"
echo -e "${GREEN}✓ Permissions policy attached${NC}"

# Step 4: Get role ARN
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Role ARN: $ROLE_ARN"
echo ""
echo "Next steps:"
echo "1. Verify the role in AWS Console: https://console.aws.amazon.com/iam/home#/roles/${ROLE_NAME}"
echo "2. Add this account to INVENTORY_ACCOUNTS environment variable (if not using Organizations)"
echo "3. Test role assumption from main account"
echo ""

