#!/usr/bin/env bash
# ============================================================
# Deploy Frontend (S3 + CloudFront) - Main Account
# Account : dcli_sharedsvcs2  (975678945875)
# ============================================================
# Usage:
#   ./deploy-frontend-main-account.sh --api-url https://xxxx.execute-api.us-east-1.amazonaws.com/dev
#   ./deploy-frontend-main-account.sh --api-url <url> --skip-build
# ============================================================

set -euo pipefail

# Defaults
PROFILE="dcli_sharedsvcs2"
REGION="us-east-1"
BUCKET_NAME="aws-inventory-dashboard-frontend-975678945875"
FRONTEND_STACK_NAME="aws-inventory-dashboard-frontend"
API_URL=""
COGNITO_USER_POOL_ID="us-east-1_CiQtVfFnM"
COGNITO_CLIENT_ID="39v2nj1ueoajpeqfrckpthd0go"
COGNITO_REGION="us-east-1"
COGNITO_DOMAIN=""
SKIP_BUILD=false
SKIP_INFRASTRUCTURE=false

# Colors
CYAN='\033[36m'
YELLOW='\033[33m'
GREEN='\033[32m'
RED='\033[31m'
RESET='\033[0m'

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)              PROFILE="$2";              shift 2 ;;
        --region)               REGION="$2";               shift 2 ;;
        --bucket-name)          BUCKET_NAME="$2";          shift 2 ;;
        --frontend-stack-name)  FRONTEND_STACK_NAME="$2";  shift 2 ;;
        --api-url)              API_URL="$2";              shift 2 ;;
        --cognito-user-pool-id) COGNITO_USER_POOL_ID="$2"; shift 2 ;;
        --cognito-client-id)    COGNITO_CLIENT_ID="$2";    shift 2 ;;
        --cognito-region)       COGNITO_REGION="$2";       shift 2 ;;
        --cognito-domain)       COGNITO_DOMAIN="$2";       shift 2 ;;
        --skip-build)           SKIP_BUILD=true;           shift   ;;
        --skip-infrastructure)  SKIP_INFRASTRUCTURE=true;  shift   ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo -e "${CYAN}============================================================${RESET}"
echo -e "${CYAN} AWS Inventory Dashboard - Frontend Deployment${RESET}"
echo -e "${CYAN} Main Account : dcli_sharedsvcs2 (975678945875)${RESET}"
echo -e "${CYAN}============================================================${RESET}"
echo ""

# Verify credentials
echo -e "${YELLOW}Verifying AWS credentials (profile: ${PROFILE})...${RESET}"
CALLER_JSON=$(aws sts get-caller-identity --profile "${PROFILE}" --region "${REGION}" --output json 2>&1) || {
    echo -e "${RED}ERROR: Cannot reach AWS with profile '${PROFILE}'. Check credentials.${RESET}"
    exit 1
}
CALLER_ACCOUNT=$(echo "${CALLER_JSON}" | grep -o '"Account": "[^"]*"' | awk -F'"' '{print $4}')
CALLER_ARN=$(echo "${CALLER_JSON}" | grep -o '"Arn": "[^"]*"' | awk -F'"' '{print $4}')
echo -e "  ${GREEN}Account: ${CALLER_ACCOUNT} | ARN: ${CALLER_ARN}${RESET}"

if [ "${CALLER_ACCOUNT}" != "975678945875" ]; then
    echo -e "${RED}WARNING: Current account (${CALLER_ACCOUNT}) != expected main account (975678945875).${RESET}"
    read -p "Continue? (yes/no): " RESP
    [ "${RESP}" != "yes" ] && exit 0
fi
echo ""

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRONTEND_DIR="$(dirname "${SCRIPT_DIR}")/frontend"

if [ ! -d "${FRONTEND_DIR}" ]; then
    echo -e "${RED}ERROR: frontend/ not found at ${FRONTEND_DIR}${RESET}"
    exit 1
fi

# Auto-detect API URL if not provided
if [ -z "${API_URL}" ]; then
    echo -e "${YELLOW}ApiUrl not provided - attempting to detect from CloudFormation stack 'inventory-dashboard'...${RESET}"
    DETECTED_URL=$(aws cloudformation describe-stacks \
        --stack-name  "inventory-dashboard" \
        --profile     "${PROFILE}" \
        --region      "${REGION}" \
        --query       "Stacks[0].Outputs[?OutputKey=='ApiUrl' || OutputKey=='ApiEndpoint' || OutputKey=='InventoryApiUrl'].OutputValue | [0]" \
        --output      text 2>/dev/null || true)
    if [ -n "${DETECTED_URL}" ] && [ "${DETECTED_URL}" != "None" ]; then
        API_URL="${DETECTED_URL}"
        echo -e "  ${GREEN}Detected API URL: ${API_URL}${RESET}"
    else
        echo -e "  ${YELLOW}WARNING: Could not auto-detect API URL. You can set it manually in .env.local later.${RESET}"
        API_URL=""
    fi
fi
echo ""

# Write .env.local
pushd "${FRONTEND_DIR}" >/dev/null

echo -e "${YELLOW}Step 1 - Writing .env.local...${RESET}"
cat > .env.local <<EOF
NEXT_PUBLIC_API_URL=${API_URL}
NEXT_PUBLIC_COGNITO_USER_POOL_ID=${COGNITO_USER_POOL_ID}
NEXT_PUBLIC_COGNITO_CLIENT_ID=${COGNITO_CLIENT_ID}
NEXT_PUBLIC_COGNITO_REGION=${COGNITO_REGION}
NEXT_PUBLIC_COGNITO_DOMAIN=${COGNITO_DOMAIN}
EOF
echo -e "  ${GREEN}.env.local written.${RESET}"
echo ""

DISTRIBUTION_ID=""

# Deploy S3/CloudFront infrastructure
if [ "${SKIP_INFRASTRUCTURE}" = false ]; then
    echo -e "${YELLOW}Step 2 - Deploying S3 + CloudFront infrastructure (CloudFormation)...${RESET}"
    INFRA_TEMPLATE="${FRONTEND_DIR}/frontend-infrastructure.yaml"
    if [ -f "${INFRA_TEMPLATE}" ]; then
        CFN_PARAMS=("ParameterKey=S3BucketName,ParameterValue=${BUCKET_NAME}")

        if aws cloudformation describe-stacks \
                --stack-name "${FRONTEND_STACK_NAME}" \
                --profile    "${PROFILE}" \
                --region     "${REGION}" \
                --output     json >/dev/null 2>&1; then
            echo -e "  ${YELLOW}Updating existing frontend stack...${RESET}"
            if aws cloudformation update-stack \
                    --stack-name    "${FRONTEND_STACK_NAME}" \
                    --template-body "file://${INFRA_TEMPLATE}" \
                    --parameters    "${CFN_PARAMS[@]}" \
                    --capabilities  CAPABILITY_IAM \
                    --profile       "${PROFILE}" \
                    --region        "${REGION}" 2>&1; then
                aws cloudformation wait stack-update-complete \
                    --stack-name "${FRONTEND_STACK_NAME}" \
                    --profile    "${PROFILE}" \
                    --region     "${REGION}"
            else
                echo -e "  ${YELLOW}Stack may already be up-to-date.${RESET}"
            fi
        else
            aws cloudformation create-stack \
                --stack-name    "${FRONTEND_STACK_NAME}" \
                --template-body "file://${INFRA_TEMPLATE}" \
                --parameters    "${CFN_PARAMS[@]}" \
                --capabilities  CAPABILITY_IAM \
                --profile       "${PROFILE}" \
                --region        "${REGION}" || {
                echo -e "${RED}ERROR: Frontend infrastructure stack creation failed.${RESET}"
                popd >/dev/null; exit 1
            }
            aws cloudformation wait stack-create-complete \
                --stack-name "${FRONTEND_STACK_NAME}" \
                --profile    "${PROFILE}" \
                --region     "${REGION}"
        fi
        echo -e "  ${GREEN}Infrastructure stack ready.${RESET}"

        # Get CloudFront distribution ID from outputs
        DISTRIBUTION_ID=$(aws cloudformation describe-stacks \
            --stack-name "${FRONTEND_STACK_NAME}" \
            --profile    "${PROFILE}" \
            --region     "${REGION}" \
            --query      "Stacks[0].Outputs[?OutputKey=='DistributionId' || OutputKey=='CloudFrontDistributionId'].OutputValue | [0]" \
            --output     text 2>/dev/null || true)
        if [ -n "${DISTRIBUTION_ID}" ] && [ "${DISTRIBUTION_ID}" != "None" ]; then
            echo -e "  ${GREEN}CloudFront Distribution ID: ${DISTRIBUTION_ID}${RESET}"
        fi
    else
        echo -e "  ${YELLOW}WARNING: frontend-infrastructure.yaml not found, skipping CloudFormation step.${RESET}"
    fi
fi
echo ""

# Build
if [ "${SKIP_BUILD}" = false ]; then
    echo -e "${YELLOW}Step 3 - Installing npm dependencies...${RESET}"
    npm install || { echo -e "${RED}ERROR: npm install failed.${RESET}"; popd >/dev/null; exit 1; }

    echo -e "${YELLOW}Step 4 - Building Next.js static export...${RESET}"
    export NEXT_EXPORT=true
    npm run build:static || { echo -e "${RED}ERROR: Build failed.${RESET}"; popd >/dev/null; exit 1; }
    echo -e "  ${GREEN}Build successful.${RESET}"
else
    echo -e "${YELLOW}Step 3/4 - Skipping build (--skip-build flag set).${RESET}"
fi
echo ""

# S3 sync
if [ ! -d "out" ]; then
    echo -e "${RED}ERROR: 'out/' directory not found. Run build first or remove --skip-build.${RESET}"
    popd >/dev/null; exit 1
fi

echo -e "${YELLOW}Step 5 - Syncing static files to s3://${BUCKET_NAME} ...${RESET}"
aws s3 sync out/ "s3://${BUCKET_NAME}" \
    --delete \
    --profile "${PROFILE}" \
    --region  "${REGION}" || {
    echo -e "${RED}ERROR: S3 sync failed.${RESET}"
    popd >/dev/null; exit 1
}
echo -e "  ${GREEN}S3 sync complete.${RESET}"
echo ""

# CloudFront invalidation
if [ -n "${DISTRIBUTION_ID}" ] && [ "${DISTRIBUTION_ID}" != "None" ]; then
    echo -e "${YELLOW}Step 6 - Invalidating CloudFront cache...${RESET}"
    aws cloudfront create-invalidation \
        --distribution-id "${DISTRIBUTION_ID}" \
        --paths           "/*" \
        --profile         "${PROFILE}"
    echo -e "  ${GREEN}Invalidation requested.${RESET}"
else
    echo -e "${YELLOW}Step 6 - Skipping CloudFront invalidation (no distribution ID found).${RESET}"
fi

popd >/dev/null

echo ""
echo -e "${GREEN}============================================================${RESET}"
echo -e "${GREEN} Frontend deployment complete!${RESET}"
echo -e "${GREEN}============================================================${RESET}"
echo ""
echo -e "${CYAN}Frontend stack outputs:${RESET}"
aws cloudformation describe-stacks \
    --stack-name "${FRONTEND_STACK_NAME}" \
    --profile    "${PROFILE}" \
    --region     "${REGION}" \
    --query      "Stacks[0].Outputs" \
    --output     table 2>/dev/null || true
