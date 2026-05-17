#!/usr/bin/env bash
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
#   ./deploy-all.sh                            # interactive (confirms each step)
#   ./deploy-all.sh --skip-confirmation        # fully automated
#   ./deploy-all.sh --steps Backend,Member     # run only specific steps
#   ./deploy-all.sh --steps Frontend --api-url https://xxx.execute-api.amazonaws.com/dev
# ============================================================

set -euo pipefail

# Defaults
STEPS="Backend,Member,Frontend"
REGION="us-east-1"
ENVIRONMENT="dev"
MAIN_PROFILE="dcli_sharedsvcs2"
MAIN_ACCOUNT_ID="975678945875"
BACKEND_STACK="inventory-dashboard"
INVENTORY_ROLE_NAME="InventoryReadRole"
INVENTORY_ACCOUNTS="529088296711:dcli_sandbox1,687360398174:dcli_sandbox2"
COGNITO_USER_POOL_ID="us-east-1_CiQtVfFnM"
COGNITO_CLIENT_ID="39v2nj1ueoajpeqfrckpthd0go"
COGNITO_REGION="us-east-1"
EXTERNAL_ID=""
BUCKET_NAME="aws-inventory-dashboard-frontend-975678945875"
FRONTEND_STACK="aws-inventory-dashboard-frontend"
API_URL=""
COGNITO_DOMAIN=""
SKIP_CONFIRMATION=false
SKIP_FRONTEND_BUILD=false

# Colors
CYAN='\033[36m'
YELLOW='\033[33m'
GREEN='\033[32m'
RED='\033[31m'
WHITE='\033[37m'
RESET='\033[0m'

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --steps)                STEPS="$2";               shift 2 ;;
        --region)               REGION="$2";              shift 2 ;;
        --environment)          ENVIRONMENT="$2";         shift 2 ;;
        --main-profile)         MAIN_PROFILE="$2";        shift 2 ;;
        --main-account-id)      MAIN_ACCOUNT_ID="$2";     shift 2 ;;
        --backend-stack)        BACKEND_STACK="$2";       shift 2 ;;
        --inventory-role-name)  INVENTORY_ROLE_NAME="$2"; shift 2 ;;
        --inventory-accounts)   INVENTORY_ACCOUNTS="$2";  shift 2 ;;
        --cognito-user-pool-id) COGNITO_USER_POOL_ID="$2"; shift 2 ;;
        --cognito-client-id)    COGNITO_CLIENT_ID="$2";   shift 2 ;;
        --cognito-region)       COGNITO_REGION="$2";      shift 2 ;;
        --external-id)          EXTERNAL_ID="$2";         shift 2 ;;
        --bucket-name)          BUCKET_NAME="$2";         shift 2 ;;
        --frontend-stack)       FRONTEND_STACK="$2";      shift 2 ;;
        --api-url)              API_URL="$2";             shift 2 ;;
        --cognito-domain)       COGNITO_DOMAIN="$2";      shift 2 ;;
        --skip-confirmation)    SKIP_CONFIRMATION=true;   shift   ;;
        --skip-frontend-build)  SKIP_FRONTEND_BUILD=true; shift   ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

write_banner() {
    local TEXT="$1"
    local COLOR="${2:-${CYAN}}"
    echo ""
    echo -e "${COLOR}============================================================${RESET}"
    echo -e "${COLOR}  ${TEXT}${RESET}"
    echo -e "${COLOR}============================================================${RESET}"
    echo ""
}

invoke_step() {
    local SCRIPT="$1"
    shift
    local FULL_PATH="${SCRIPT_DIR}/${SCRIPT}"
    if [ ! -f "${FULL_PATH}" ]; then
        echo -e "${RED}ERROR: Script not found: ${FULL_PATH}${RESET}"
        exit 1
    fi
    echo -e "${CYAN}Running: ${SCRIPT}${RESET}"
    bash "${FULL_PATH}" "$@"
    local EXIT_CODE=$?
    if [ ${EXIT_CODE} -ne 0 ]; then
        echo -e "${RED}ERROR: ${SCRIPT} failed (exit code ${EXIT_CODE}).${RESET}"
        exit ${EXIT_CODE}
    fi
}

write_banner "AWS Inventory Dashboard - Master Deployment" "${CYAN}"
echo -e "  ${YELLOW}Main account : ${MAIN_PROFILE} (${MAIN_ACCOUNT_ID})${RESET}"
echo -e "  ${YELLOW}Client accts : dcli_sandbox1 (529088296711)${RESET}"
echo -e "  ${YELLOW}               dcli_sandbox2 (687360398174)${RESET}"
echo -e "  ${YELLOW}Region       : ${REGION}${RESET}"
echo -e "  ${YELLOW}Environment  : ${ENVIRONMENT}${RESET}"
echo -e "  ${YELLOW}Steps        : ${STEPS}${RESET}"
echo ""

if [ "${SKIP_CONFIRMATION}" = false ]; then
    read -p "Proceed with deployment? (yes/no): " RESP
    if [ "${RESP}" != "yes" ]; then
        echo -e "${YELLOW}Aborted.${RESET}"; exit 0
    fi
fi

# ================================================================
# STEP 1 - BACKEND
# ================================================================
if echo "${STEPS}" | grep -qi "Backend"; then
    write_banner "STEP 1 / 3 - Backend (SAM)" "${YELLOW}"

    BACKEND_ARGS=(
        "--profile"              "${MAIN_PROFILE}"
        "--region"               "${REGION}"
        "--environment"          "${ENVIRONMENT}"
        "--stack-name"           "${BACKEND_STACK}"
        "--inventory-role-name"  "${INVENTORY_ROLE_NAME}"
        "--inventory-accounts"   "${INVENTORY_ACCOUNTS}"
        "--cognito-user-pool-id" "${COGNITO_USER_POOL_ID}"
        "--cognito-client-id"    "${COGNITO_CLIENT_ID}"
        "--cognito-region"       "${COGNITO_REGION}"
        "--external-id"          "${EXTERNAL_ID}"
    )
    [ "${SKIP_CONFIRMATION}" = true ] && BACKEND_ARGS+=("--skip-confirmation")

    invoke_step "deploy-backend-main-account.sh" "${BACKEND_ARGS[@]}"

    # Auto-detect API URL for use in frontend step
    if [ -z "${API_URL}" ]; then
        echo -e "${CYAN}Detecting API URL from stack outputs...${RESET}"
        DETECTED=$(aws cloudformation describe-stacks \
            --stack-name  "${BACKEND_STACK}" \
            --profile     "${MAIN_PROFILE}" \
            --region      "${REGION}" \
            --query       "Stacks[0].Outputs[?OutputKey=='ApiUrl' || OutputKey=='ApiEndpoint' || OutputKey=='InventoryApiUrl'].OutputValue | [0]" \
            --output      text 2>/dev/null || true)
        if [ -n "${DETECTED}" ] && [ "${DETECTED}" != "None" ]; then
            API_URL="${DETECTED}"
            echo -e "  ${GREEN}API URL: ${API_URL}${RESET}"
        fi
    fi
fi

# ================================================================
# STEP 2 - MEMBER ACCOUNT ROLES
# ================================================================
if echo "${STEPS}" | grep -qi "Member"; then
    write_banner "STEP 2 / 3 - Member Account Roles" "${YELLOW}"

    MEMBER_ARGS=(
        "--main-account-id" "${MAIN_ACCOUNT_ID}"
        "--region"          "${REGION}"
        "--role-name"       "${INVENTORY_ROLE_NAME}"
        "--external-id"     "${EXTERNAL_ID}"
    )
    [ "${SKIP_CONFIRMATION}" = true ] && MEMBER_ARGS+=("--skip-confirmation")

    invoke_step "deploy-member-account-roles.sh" "${MEMBER_ARGS[@]}"
fi

# ================================================================
# STEP 3 - FRONTEND
# ================================================================
if echo "${STEPS}" | grep -qi "Frontend"; then
    write_banner "STEP 3 / 3 - Frontend (S3 + CloudFront)" "${YELLOW}"

    FRONTEND_ARGS=(
        "--profile"           "${MAIN_PROFILE}"
        "--region"            "${REGION}"
        "--bucket-name"       "${BUCKET_NAME}"
        "--frontend-stack-name" "${FRONTEND_STACK}"
        "--api-url"           "${API_URL}"
        "--cognito-user-pool-id" "${COGNITO_USER_POOL_ID}"
        "--cognito-client-id" "${COGNITO_CLIENT_ID}"
        "--cognito-region"    "${COGNITO_REGION}"
        "--cognito-domain"    "${COGNITO_DOMAIN}"
    )
    [ "${SKIP_FRONTEND_BUILD}" = true ] && FRONTEND_ARGS+=("--skip-build")

    invoke_step "deploy-frontend-main-account.sh" "${FRONTEND_ARGS[@]}"
fi

# ================================================================
# DONE
# ================================================================
write_banner "All requested deployment steps completed successfully!" "${GREEN}"
echo -e "${CYAN}Summary:${RESET}"
echo -e "  ${WHITE}Backend stack  : ${BACKEND_STACK}   (profile: ${MAIN_PROFILE})${RESET}"
echo -e "  ${WHITE}Member roles   : InventoryReadRole in dcli_sandbox1 + dcli_sandbox2${RESET}"
echo -e "  ${WHITE}Frontend stack : ${FRONTEND_STACK}  (profile: ${MAIN_PROFILE})${RESET}"
echo ""
echo -e "${CYAN}To verify, open the CloudFront URL from the frontend stack outputs.${RESET}"
