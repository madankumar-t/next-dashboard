# AWS Inventory Dashboard - Complete Deployment Instructions

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Phase 1: Backend Deployment](#phase-1-backend-deployment)
4. [Phase 2: Member Account Setup](#phase-2-member-account-setup)
5. [Phase 3: Frontend Deployment](#phase-3-frontend-deployment)
6. [Automated All-in-One Deployment](#automated-all-in-one-deployment)
7. [Verification & Testing](#verification--testing)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Software
- **AWS CLI v2** - Latest version installed and configured
- **SAM CLI** - AWS Serverless Application Model CLI
- **Node.js 18+** - For frontend build
- **npm or yarn** - Package manager
- **Python 3.12** - For backend validation
- **PowerShell 5.1+** (Windows) OR **Bash 4.0+** (Linux/Mac)

### AWS Permissions Required
- EC2, S3, Lambda, CloudFormation, IAM, CloudFront, DynamoDB, CloudWatch, API Gateway, Cognito

### Information You Need
```bash
# Get these values first:
aws sts get-caller-identity --query Account --output text          # Main Account ID
aws sts get-caller-identity --query Arn --output text              # Your ARN
aws organizations list-accounts --query "Accounts[*].[Id,Name]"    # Member Accounts (if using Org)
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Main Account (Hub)                        │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Lambda (InventoryRefreshFunction)                   │   │
│  │  - Collects inventory from accounts                  │   │
│  │  - Stores in DynamoDB                               │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  API Gateway + Cognito Authentication               │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Frontend (Next.js) on S3 + CloudFront              │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
   AssumeRole        AssumeRole        AssumeRole
        │                 │                 │
    ┌───▼────┐       ┌────▼───┐       ┌────▼────┐
    │Member A │       │Member B │       │Member C │
    │Account  │       │Account  │       │Account  │
    └────────┘       └────────┘       └────────┘
```

---

# PHASE 1: Backend Deployment

Deploy Lambda, API Gateway, DynamoDB to your main account.

## Step 1.1: Prepare Configuration

```bash
# Navigate to backend directory
cd backend

# Review the SAM template
cat template.yaml

# Check Python version
python --version    # Should be 3.12+
```

## Step 1.2: Update SAM Configuration (if needed)

Edit `backend/samconfig.toml`:

```toml
version=0.1
[default]
[default.deploy]
region = "us-east-1"
s3_bucket = "aws-inventory-backend-ACCOUNT_ID"
s3_prefix = "inventory-dashboard"
parameter_overrides = "Environment=dev InventoryAccounts=123456789012:AccountA,987654321098:AccountB"
```

## Step 1.3: Build Backend

```bash
cd backend

# Install Python dependencies (optional - SAM handles this)
pip install -r requirements.txt

# Validate SAM template
sam validate --template template.yaml

# Build SAM project
sam build
```

**Expected Output:**
```
Build Succeeded
```

## Step 1.4: Deploy Backend (Choose One)

### Option A: Interactive Deployment (Recommended for first-time)

**Windows (PowerShell):**
```powershell
cd scripts
.\deploy-backend-main-account.ps1 `
  -Profile your-aws-profile `
  -Region us-east-1 `
  -Environment dev
```

**Linux/Mac (Bash):**
```bash
cd scripts
chmod +x deploy-backend-main-account.sh
./deploy-backend-main-account.sh \
  --profile your-aws-profile \
  --region us-east-1 \
  --environment dev
```

### Option B: Manual Deployment

```bash
cd backend

# Define parameters
MAIN_ACCOUNT_ID="YOUR_ACCOUNT_ID"
REGION="us-east-1"
ENVIRONMENT="dev"
INVENTORY_ROLE_NAME="InventoryReadRole"
INVENTORY_ACCOUNTS="123456789012:Account1,987654321098:Account2"

# Deploy with SAM
sam deploy \
  --stack-name inventory-dashboard \
  --region "${REGION}" \
  --capabilities CAPABILITY_IAM \
  --resolve-s3 \
  --s3-prefix inventory-dashboard \
  --parameter-overrides \
    Environment="${ENVIRONMENT}" \
    InventoryRoleName="${INVENTORY_ROLE_NAME}" \
    InventoryAccounts="${INVENTORY_ACCOUNTS}" \
  --confirm-changeset
```

## Step 1.5: Get Backend Outputs

```bash
# Get CloudFormation stack outputs
aws cloudformation describe-stacks \
  --stack-name inventory-dashboard \
  --query "Stacks[0].Outputs" \
  --output table

# Specifically get API URL (needed for frontend)
API_URL=$(aws cloudformation describe-stacks \
  --stack-name inventory-dashboard \
  --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" \
  --output text)

echo "API URL: $API_URL"
```

**Save these values:**
- `ApiUrl` - API Gateway endpoint
- `LambdaFunctionName` - Lambda function name
- `DynamoDBTableName` - DynamoDB table name

## Step 1.6: Verify Backend

```bash
# Check CloudFormation stack
aws cloudformation describe-stacks \
  --stack-name inventory-dashboard \
  --query "Stacks[0].StackStatus" \
  --output text
# Expected: CREATE_COMPLETE or UPDATE_COMPLETE

# Check Lambda function
aws lambda list-functions \
  --query "Functions[?contains(FunctionName, 'inventory')].{Name:FunctionName,Status:LastUpdateStatus}" \
  --output table

# Check Lambda logs
aws logs tail /aws/lambda/inventory-dashboard-RefreshFunction --follow
```

---

# PHASE 2: Member Account Setup

Create IAM roles in each member/client account that the Lambda function can assume.

## Step 2.1: Gather Information

From Phase 1, you need:
```bash
# Main Account ID
MAIN_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Lambda Execution Role Name (from backend stack outputs)
LAMBDA_ROLE_NAME=$(aws cloudformation describe-stacks \
  --stack-name inventory-dashboard \
  --query 'Stacks[0].Outputs[?OutputKey=="LambdaExecutionRole"].OutputValue' \
  --output text | cut -d'/' -f2)

echo "Main Account: $MAIN_ACCOUNT_ID"
echo "Lambda Role: $LAMBDA_ROLE_NAME"
```

## Step 2.2: Switch to Member Account

```bash
# Option 1: Using AWS profile
export AWS_PROFILE=member-account-profile

# Option 2: Using assume-role
aws sts assume-role \
  --role-arn arn:aws:iam::MEMBER_ACCOUNT_ID:role/AdminRole \
  --role-session-name inventory-setup

# Verify you're in the member account
aws sts get-caller-identity --query Account --output text
# Should show MEMBER_ACCOUNT_ID
```

## Step 2.3: Create Member Account Role (Choose One)

### Option A: Using Script (Easiest)

**Windows (PowerShell):**
```powershell
cd scripts
.\create-cross-account-role-complete.ps1 `
  -MemberAccountId MEMBER_ACCOUNT_ID `
  -MainAccountId MAIN_ACCOUNT_ID `
  -ExternalId "optional-external-id"
```

**Linux/Mac (Bash):**
```bash
cd scripts
chmod +x create-cross-account-role-complete.sh

./create-cross-account-role-complete.sh \
  MEMBER_ACCOUNT_ID \
  MAIN_ACCOUNT_ID \
  "LAMBDA_ROLE_NAME" \
  "optional-external-id" \
  "InventoryReadRole"
```

### Option B: Using CloudFormation

```bash
# Switch to member account first!
export AWS_PROFILE=member-account-profile

# Deploy the template
aws cloudformation create-stack \
  --stack-name inventory-read-role \
  --template-body file://member-account-role.yaml \
  --parameters \
    ParameterKey=MainAccountId,ParameterValue=MAIN_ACCOUNT_ID \
    ParameterKey=ExternalId,ParameterValue="optional-external-id" \
  --capabilities CAPABILITY_NAMED_IAM

# Wait for completion
aws cloudformation wait stack-create-complete \
  --stack-name inventory-read-role
```

### Option C: Manual Creation via AWS Console

1. Go to **IAM** → **Roles** → **Create role**
2. Select **AWS account** → **Another AWS account**
3. Enter **Main Account ID**: `MAIN_ACCOUNT_ID`
4. (Optional) Check "Require external ID"
5. Click **Next**
6. Search for and attach: `ReadOnlyAccess` (or use custom policy from [policies/inventory-read-policy.json](policies/inventory-read-policy.json))
7. Name role: `InventoryReadRole`
8. Click **Create role**

## Step 2.4: Verify Member Account Role

```bash
# Switch back to main account
export AWS_PROFILE=main-account-profile

# Test assume role
ROLE_ARN="arn:aws:iam::MEMBER_ACCOUNT_ID:role/InventoryReadRole"

aws sts assume-role \
  --role-arn "${ROLE_ARN}" \
  --role-session-name test-inventory \
  --external-id "optional-external-id"

# If successful, you'll see credentials in the output
```

## Step 2.5: Repeat for All Member Accounts

Repeat Steps 2.2-2.4 for each member/client account.

**For AWS Organizations users:** Roles may be auto-discovered, check Lambda logs.

---

# PHASE 3: Frontend Deployment

Deploy Next.js frontend to S3 + CloudFront.

## Step 3.1: Prepare Frontend Configuration

```bash
cd frontend

# Install dependencies
npm install

# Create environment file
cat > .env.local <<EOF
NEXT_PUBLIC_API_URL=YOUR_API_URL
NEXT_PUBLIC_COGNITO_USER_POOL_ID=YOUR_USER_POOL_ID
NEXT_PUBLIC_COGNITO_CLIENT_ID=YOUR_CLIENT_ID
NEXT_PUBLIC_COGNITO_REGION=us-east-1
NEXT_PUBLIC_COGNITO_DOMAIN=your-domain
EOF
```

**Replace with actual values from:**
- API URL: From Phase 1.5
- Cognito credentials: From your Cognito User Pool (AWS Cognito console)

## Step 3.2: Build Frontend

```bash
cd frontend

# Build Next.js
npm run build

# Test locally (optional)
npm run dev
# Visit http://localhost:3000
```

**Expected Output:**
```
✓ Compiled successfully
✓ Linting and checking validity of types
✓ Collecting page data
✓ Generating static pages
```

## Step 3.3: Deploy Frontend (Choose One)

### Option A: Using Script (Recommended)

**Windows (PowerShell):**
```powershell
cd scripts
.\deploy-frontend-main-account.ps1 `
  -ApiUrl "YOUR_API_URL" `
  -Profile your-aws-profile
```

**Linux/Mac (Bash):**
```bash
cd scripts
chmod +x deploy-frontend-main-account.sh

./deploy-frontend-main-account.sh \
  --api-url "YOUR_API_URL" \
  --profile your-aws-profile
```

### Option B: Manual Deployment

```bash
cd frontend

# Build
npm run build

# Create S3 bucket (if not exists)
BUCKET_NAME="aws-inventory-dashboard-frontend-ACCOUNT_ID"
aws s3 mb s3://${BUCKET_NAME} --region us-east-1

# Upload to S3
aws s3 sync out/ s3://${BUCKET_NAME}/ --delete

# Deploy CloudFront (if using existing CloudFormation)
aws cloudformation update-stack \
  --stack-name aws-inventory-dashboard-frontend \
  --template-body file://frontend-infrastructure.yaml \
  --parameters ParameterKey=S3BucketName,ParameterValue=${BUCKET_NAME} \
  --capabilities CAPABILITY_IAM
```

## Step 3.4: Get Frontend URL

```bash
# Get CloudFront distribution URL
aws cloudformation describe-stacks \
  --stack-name aws-inventory-dashboard-frontend \
  --query "Stacks[0].Outputs[?OutputKey=='CloudFrontUrl'].OutputValue" \
  --output text
```

---

# AUTOMATED ALL-IN-ONE DEPLOYMENT

Deploy everything in one command!

## Windows (PowerShell)

```powershell
cd scripts

.\deploy-all.ps1 `
  -SkipConfirmation `
  -MainProfile "your-aws-profile" `
  -MainAccountId "YOUR_ACCOUNT_ID" `
  -Region "us-east-1" `
  -Environment "dev"
```

## Linux/Mac (Bash)

```bash
cd scripts
chmod +x deploy-all.sh

./deploy-all.sh \
  --skip-confirmation \
  --main-profile "your-aws-profile" \
  --main-account-id "YOUR_ACCOUNT_ID" \
  --region "us-east-1" \
  --environment "dev"
```

**What this does:**
1. ✅ Deploys backend (Lambda, API Gateway, DynamoDB)
2. ✅ Creates member account roles
3. ✅ Builds and deploys frontend
4. ✅ Outputs all URLs and credentials

---

# VERIFICATION & TESTING

## Test 1: Backend Health Check

```bash
# Get API URL
API_URL=$(aws cloudformation describe-stacks \
  --stack-name inventory-dashboard \
  --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" \
  --output text)

# Test API
curl -X GET "${API_URL}/health" -H "Content-Type: application/json"

# Expected response:
# { "status": "healthy", "timestamp": "2024-..." }
```

## Test 2: Lambda Function

```bash
# Get Lambda function name
LAMBDA_FUNCTION=$(aws cloudformation describe-stacks \
  --stack-name inventory-dashboard \
  --query "Stacks[0].Outputs[?OutputKey=='LambdaFunctionName'].OutputValue" \
  --output text)

# Invoke Lambda manually
aws lambda invoke \
  --function-name "${LAMBDA_FUNCTION}" \
  --payload file://test-payload.json \
  response.json

# Check response
cat response.json
```

## Test 3: Frontend Access

```bash
# Get CloudFront URL
FRONTEND_URL=$(aws cloudformation describe-stacks \
  --stack-name aws-inventory-dashboard-frontend \
  --query "Stacks[0].Outputs[?OutputKey=='CloudFrontUrl'].OutputValue" \
  --output text)

echo "Frontend: ${FRONTEND_URL}"
# Visit in browser and login with Cognito credentials
```

## Test 4: Cross-Account Access

```bash
# Verify Lambda can assume member account role
aws logs tail /aws/lambda/inventory-dashboard-RefreshFunction \
  --follow \
  --filter-pattern "AssumeRole"

# Should see successful role assumption
```

---

# TROUBLESHOOTING

## Backend Deployment Issues

### "sam build" fails

```bash
# Solution: Install dependencies first
cd backend
pip install -r requirements.txt
python -m pip install --upgrade pip
sam build --debug
```

### "Access Denied" during deployment

```bash
# Check credentials
aws sts get-caller-identity

# Check IAM permissions
# Required: CloudFormation, Lambda, DynamoDB, API Gateway, IAM, CloudWatch, S3
```

### Lambda environment variables not set

```bash
# Update Lambda environment
aws lambda update-function-configuration \
  --function-name inventory-dashboard-RefreshFunction \
  --environment Variables={INVENTORY_ACCOUNTS=123456789012:AccountA,987654321098:AccountB}
```

## Frontend Deployment Issues

### "NEXT_PUBLIC_API_URL" not set

```bash
# Edit .env.local
cd frontend
cat > .env.local <<EOF
NEXT_PUBLIC_API_URL=https://your-api-endpoint.execute-api.us-east-1.amazonaws.com/prod
NEXT_PUBLIC_COGNITO_USER_POOL_ID=us-east-1_xxxxx
NEXT_PUBLIC_COGNITO_CLIENT_ID=your-client-id
NEXT_PUBLIC_COGNITO_REGION=us-east-1
NEXT_PUBLIC_COGNITO_DOMAIN=your-domain
EOF

# Rebuild
npm run build
```

### CloudFront cache issues

```bash
# Invalidate CloudFront cache
DISTRIBUTION_ID=$(aws cloudformation describe-stacks \
  --stack-name aws-inventory-dashboard-frontend \
  --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDistributionId'].OutputValue" \
  --output text)

aws cloudfront create-invalidation \
  --distribution-id "${DISTRIBUTION_ID}" \
  --paths "/*"
```

## Member Account Role Issues

### "Access Denied" when assuming role

```bash
# Verify trust policy
MEMBER_ACCOUNT_ID="123456789012"
aws iam get-role \
  --role-name InventoryReadRole \
  --query "Role.AssumeRolePolicyDocument"

# Should show your main account's Lambda role in the principal
```

### Role not found in member account

```bash
# Verify you're in the member account
aws sts get-caller-identity

# List roles
aws iam list-roles --query "Roles[?contains(RoleName, 'Inventory')].RoleName"

# If empty, create role again (see Phase 2)
```

## Logging & Debugging

```bash
# Backend logs
aws logs tail /aws/lambda/inventory-dashboard-RefreshFunction --follow --since 1h

# API Gateway logs
aws logs tail /aws/apigateway/inventory-dashboard --follow

# CloudFront logs
aws cloudfront list-distributions-by-origin-request-policy-id \
  --origin-request-policy-id-marker 216adef5-5c7f-47e4-b989-5492eafa07d3

# Check CloudFormation events
aws cloudformation describe-stack-events \
  --stack-name inventory-dashboard \
  --query "StackEvents[0:10]"
```

---

## Quick Reference: File Paths

| Component | Location | Script |
|-----------|----------|--------|
| Backend | `backend/` | `deploy-backend-main-account.sh` |
| Frontend | `frontend/` | `deploy-frontend-main-account.sh` |
| Member Role | `member-account-role.yaml` | `create-cross-account-role-complete.sh` |
| Policies | `scripts/policies/` | N/A |
| Master Deploy | `scripts/` | `deploy-all.sh` |

---

## Summary of Commands

**First-time deployment:**
```bash
# 1. Backend
cd scripts
./deploy-backend-main-account.sh --profile main --region us-east-1 --environment dev

# 2. Member Accounts
./create-cross-account-role-complete.sh MEMBER_ID MAIN_ID

# 3. Frontend
./deploy-frontend-main-account.sh --api-url https://xxx.execute-api.us-east-1.amazonaws.com/dev

# OR all-in-one
./deploy-all.sh --skip-confirmation
```

**Updating existing deployment:**
```bash
# Backend update
cd backend && sam build && sam deploy --guided

# Frontend update
cd frontend && npm run build && npm run deploy

# Member account update
./create-cross-account-role-complete.sh MEMBER_ID MAIN_ID
```

---

For detailed troubleshooting, see individual guides:
- [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)
- [MULTI_ACCOUNT_SETUP.md](MULTI_ACCOUNT_SETUP.md)
- [FRONTEND_DEPLOYMENT.md](frontend/FRONTEND_DEPLOYMENT.md)
