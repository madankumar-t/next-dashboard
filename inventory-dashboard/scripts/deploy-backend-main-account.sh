#!/usr/bin/env bash
# ============================================================
# Deploy Backend (SAM) - Main Account
# Account : dcli_sharedsvcs2  (975678945875)
# ============================================================
# Usage:
#   ./deploy-backend-main-account.sh
#   ./deploy-backend-main-account.sh --environment prod
#   ./deploy-backend-main-account.sh --skip-confirmation
# ============================================================

set -euo pipefail

# Defaults
ENVIRONMENT="dev"
PROFILE="dcli_sharedsvcs2"
REGION="us-east-1"
STACK_NAME="inventory-dashboard"
INVENTORY_ROLE_NAME="InventoryReadRole"
INVENTORY_ACCOUNTS="529088296711:dcli_sandbox1,687360398174:dcli_sandbox2"
COGNITO_USER_POOL_ID="us-east-1_CiQtVfFnM"
COGNITO_CLIENT_ID="39v2nj1ueoajpeqfrckpthd0go"
COGNITO_REGION="us-east-1"
EXTERNAL_ID=""
SKIP_CONFIRMATION=false

# Colors
CYAN='\033[36m'
YELLOW='\033[33m'
GREEN='\033[32m'
RED='\033[31m'
RESET='\033[0m'

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --environment)        ENVIRONMENT="$2";        shift 2 ;;
        --profile)            PROFILE="$2";            shift 2 ;;
        --region)             REGION="$2";             shift 2 ;;
        --stack-name)         STACK_NAME="$2";         shift 2 ;;
        --inventory-role-name) INVENTORY_ROLE_NAME="$2"; shift 2 ;;
        --inventory-accounts) INVENTORY_ACCOUNTS="$2"; shift 2 ;;
        --cognito-user-pool-id) COGNITO_USER_POOL_ID="$2"; shift 2 ;;
        --cognito-client-id)  COGNITO_CLIENT_ID="$2";  shift 2 ;;
        --cognito-region)     COGNITO_REGION="$2";     shift 2 ;;
        --external-id)        EXTERNAL_ID="$2";        shift 2 ;;
        --skip-confirmation)  SKIP_CONFIRMATION=true;  shift   ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo -e "${CYAN}============================================================${RESET}"
echo -e "${CYAN} AWS Inventory Dashboard - Backend Deployment${RESET}"
echo -e "${CYAN} Main Account : dcli_sharedsvcs2 (975678945875)${RESET}"
echo -e "${CYAN}============================================================${RESET}"
echo ""
echo -e "${YELLOW}  Profile    : ${PROFILE}${RESET}"
echo -e "${YELLOW}  Region     : ${REGION}${RESET}"
echo -e "${YELLOW}  Stack      : ${STACK_NAME}${RESET}"
echo -e "${YELLOW}  Environment: ${ENVIRONMENT}${RESET}"
echo -e "${YELLOW}  Accounts   : ${INVENTORY_ACCOUNTS}${RESET}"
echo ""

# Verify caller identity
echo -e "${CYAN}Verifying AWS credentials...${RESET}"
CALLER_JSON=$(aws sts get-caller-identity --profile "${PROFILE}" --region "${REGION}" --output json 2>&1) || {
    echo -e "${RED}ERROR: Cannot reach AWS with profile '${PROFILE}'. Check credentials.${RESET}"
    exit 1
}
CALLER_ACCOUNT=$(echo "${CALLER_JSON}" | grep -o '"Account": "[^"]*"' | awk -F'"' '{print $4}')
CALLER_USER_ID=$(echo "${CALLER_JSON}" | grep -o '"UserId": "[^"]*"' | awk -F'"' '{print $4}')
CALLER_ARN=$(echo "${CALLER_JSON}" | grep -o '"Arn": "[^"]*"' | awk -F'"' '{print $4}')
echo -e "  ${GREEN}Account  : ${CALLER_ACCOUNT}${RESET}"
echo -e "  ${GREEN}UserId   : ${CALLER_USER_ID}${RESET}"
echo -e "  ${GREEN}ARN      : ${CALLER_ARN}${RESET}"

if [ "${CALLER_ACCOUNT}" != "975678945875" ]; then
    echo ""
    echo -e "${RED}WARNING: Current account (${CALLER_ACCOUNT}) does not match expected main account (975678945875).${RESET}"
    if [ "${SKIP_CONFIRMATION}" = false ]; then
        read -p "Continue anyway? (yes/no): " RESP
        if [ "${RESP}" != "yes" ]; then
            echo -e "${YELLOW}Aborted.${RESET}"; exit 0
        fi
    fi
fi
echo ""

# Move into backend folder
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$(dirname "${SCRIPT_DIR}")/backend"

if [ ! -d "${BACKEND_DIR}" ]; then
    echo -e "${RED}ERROR: backend/ folder not found at ${BACKEND_DIR}${RESET}"
    exit 1
fi

pushd "${BACKEND_DIR}" >/dev/null
echo -e "${CYAN}Working directory: ${BACKEND_DIR}${RESET}"
echo ""

# sam build
echo -e "${YELLOW}Step 1 of 2 - Building SAM application...${RESET}"
sam build --profile "${PROFILE}" --region "${REGION}" || {
    echo -e "${RED}ERROR: sam build failed.${RESET}"
    popd >/dev/null; exit 1
}
echo -e "${GREEN}Build successful.${RESET}"
echo ""

# sam deploy
echo -e "${YELLOW}Step 2 of 2 - Deploying to AWS (profile: ${PROFILE})...${RESET}"

PARAM_OVERRIDES=(
    "Environment=${ENVIRONMENT}"
    "ExternalId=${EXTERNAL_ID}"
    "InventoryRoleName=${INVENTORY_ROLE_NAME}"
    "InventoryAccounts=${INVENTORY_ACCOUNTS}"
    "ExistingCognitoUserPoolId=${COGNITO_USER_POOL_ID}"
    "ExistingCognitoClientId=${COGNITO_CLIENT_ID}"
    "CognitoRegion=${COGNITO_REGION}"
)

if [ "${SKIP_CONFIRMATION}" = true ]; then
    CONFIRM_FLAG="--no-confirm-changeset"
else
    CONFIRM_FLAG="--confirm-changeset"
fi

sam deploy \
    --stack-name          "${STACK_NAME}" \
    --profile             "${PROFILE}" \
    --region              "${REGION}" \
    --capabilities        CAPABILITY_IAM \
    --resolve-s3 \
    --s3-prefix           "${STACK_NAME}" \
    --parameter-overrides "${PARAM_OVERRIDES[@]}" \
    ${CONFIRM_FLAG} \
    --disable-rollback || {
    echo -e "${RED}ERROR: sam deploy failed.${RESET}"
    popd >/dev/null; exit 1
}

popd >/dev/null

echo ""
echo -e "${GREEN}============================================================${RESET}"
echo -e "${GREEN} Backend deployment complete!${RESET}"
echo -e "${GREEN}============================================================${RESET}"
echo ""

# Collect outputs
echo -e "${CYAN}Stack outputs:${RESET}"
aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --profile    "${PROFILE}" \
    --region     "${REGION}" \
    --query      "Stacks[0].Outputs" \
    --output     table

echo ""
echo -e "${CYAN}Next steps:${RESET}"
echo "  1. Note the API Gateway URL from the outputs above."
echo "  2. Run   ./deploy-member-account-roles.sh   to set up sandbox accounts."
echo "  3. Run   ./deploy-frontend-main-account.sh  to deploy the frontend."
