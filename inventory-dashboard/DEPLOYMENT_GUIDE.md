# AWS Inventory Dashboard - Complete Deployment Guide

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Quick Start (All-in-One)](#quick-start-all-in-one)
4. [Step-by-Step Backend Deployment](#step-by-step-backend-deployment)
5. [Step-by-Step Frontend Deployment](#step-by-step-frontend-deployment)
6. [Step-by-Step Cross-Account Role Setup](#step-by-step-cross-account-role-setup)
7. [Verification & Testing](#verification--testing)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Software
- **AWS CLI v2** - Latest version installed and configured
- **SAM CLI** - For Lambda deployment (`sam --version`)
- **Node.js 18+** - For frontend build
- **npm** or **yarn** - Package manager for frontend
- **Python 3.12** - For backend validation
- **PowerShell 5.1+** (Windows) OR **Bash 4.0+** (Linux/Mac)

### AWS Account Setup
- **Main Account**: Where Lambda, API Gateway, and CloudFront will be deployed
- **Member Accounts**: Each account where you want to collect inventory
- **IAM Permissions**: Full EC2, S3, Lambda, CloudFormation, IAM, and CloudFront permissions

### Get Your Account IDs

```bash
# Get Main Account ID
aws sts get-caller-identity --query Account --output text

# List all accounts (if using AWS Organizations)
aws organizations list-accounts --query "Accounts[*].[Id,Name]" --output text
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Main Account (Hub)                        │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Lambda Function (InventoryRefreshFunction)         │   │
│  │  - Collects inventory from multiple accounts        │   │
│  │  - Stores data in DynamoDB                          │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  API Gateway                                         │   │
│  │  - Provides REST API for frontend                   │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Frontend (S3 + CloudFront)                         │   │
│  │  - Next.js application deployed to S3              │   │
│  │  - Cached globally via CloudFront                  │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                          │
                ┌─────────┼─────────┐
                │         │         │
         AssumeRole  AssumeRole  AssumeRole
                │         │         │
        ┌───────▼──┐ ┌────▼──────┐ ┌───────▼───┐
        │ Member   │ │ Member    │ │ Member    │
        │Account A │ │ Account B │ │ Account C │
        │          │ │           │ │           │
        │InventoryRead Roles (Assume by Main Account Lambda)
        └──────────┘ └───────────┘ └───────────┘
```

---

## Quick Start (All-in-One)

For experienced AWS users, use the master deployment script to deploy everything:

### Windows (PowerShell)
```powershell
cd scripts
.\deploy-all.ps1 -SkipConfirmation
```

### Linux/Mac (Bash)
```bash
cd scripts
chmod +x deploy-all.sh
./deploy-all.sh --skip-confirmation
```

**What this does:**
1. Deploys Lambda, API Gateway, and DynamoDB (Backend)
2. Creates InventoryReadRole in each member account
3. Deploys Next.js frontend to S3 + CloudFront

**Note**: You'll need to configure AWS profiles and parameters before running the master script.

---

## Step-by-Step Backend Deployment

### Step 1: Prepare Backend Configuration

1. **Navigate to backend directory**
   ```bash
   cd backend
   ```

2. **Review the SAM template**
   ```bash
   cat template.yaml | grep -A 5 "Parameters:"
   ```

3. **Create/Update samconfig.toml** (if needed)
   ```toml
   version=0.1
   [default]
   [default.deploy]
   region = "us-east-1"
   s3_bucket = "aws-inventory-backend-deployment-ACCOUNT_ID"
   s3_prefix = "inventory-dashboard"
   parameter_overrides = "Environment=dev ExistingCognitoUserPoolId=us-east-1_XXXXXXXXX ExistingCognitoClientId=YYYYYYYYYY"
   ```

### Step 2: Build Backend

```bash
cd backend

# Install dependencies
pip install -r requirements.txt

# Validate SAM template
sam validate --template template.yaml

# Build SAM project
sam build
```

### Step 3: Deploy Backend

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

### Step 4: Verify Backend Deployment

1. **Check CloudFormation stack**
   ```bash
   aws cloudformation describe-stacks \
     --stack-name inventory-dashboard \
     --query "Stacks[0].StackStatus" \
     --output text
   ```
   Expected output: `CREATE_COMPLETE` or `UPDATE_COMPLETE`

2. **Get API Gateway URL**
   ```bash
   aws cloudformation describe-stacks \
     --stack-name inventory-dashboard \
     --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" \
     --output text
   ```
   Save this URL - you'll need it for frontend configuration.

3. **Check Lambda function**
   ```bash
   aws lambda list-functions --query "Functions[?contains(FunctionName, 'inventory')].{Name:FunctionName,Status:LastUpdateStatus}" --output table
   ```

4. **View Lambda logs**
   ```bash
   aws logs tail /aws/lambda/inventory-dashboard-RefreshFunction --follow
   ```

### Step 5: Update Backend Parameters (if needed)

If you need to add/remove member accounts or change settings:

```bash
aws cloudformation update-stack \
  --stack-name inventory-dashboard \
  --use-previous-template \
  --parameters \
    ParameterKey=InventoryAccounts,ParameterValue="123456789012:Account1,210987654321:Account2" \
    ParameterKey=ExternalId,ParameterValue="your-external-id" \
  --capabilities CAPABILITY_IAM
```

---

## Step-by-Step Frontend Deployment

### Step 1: Prepare Frontend Configuration

1. **Navigate to frontend directory**
   ```bash
   cd frontend
   ```

2. **Install dependencies**
   ```bash
   npm install
   # or
   yarn install
   ```

3. **Create `.env.local` file** (if deploying locally first)
   ```bash
   cat > .env.local << EOF
   NEXT_PUBLIC_API_URL=https://YOUR_API_GATEWAY_URL
   NEXT_PUBLIC_COGNITO_DOMAIN=https://your-cognito-domain
   NEXT_PUBLIC_COGNITO_CLIENT_ID=your-cognito-client-id
   NEXT_PUBLIC_COGNITO_REGION=us-east-1
   NEXT_PUBLIC_COGNITO_REDIRECT_URI=https://your-cloudfront-domain/callback
   EOF
   ```

### Step 2: Build Frontend

```bash
cd frontend

# Build Next.js application (produces optimized static files)
npm run build

# Verify build completed successfully
ls -la .next
```

### Step 3: Deploy Frontend

**Windows (PowerShell):**
```powershell
cd scripts
.\deploy-frontend-main-account.ps1 `
  -Profile your-aws-profile `
  -Region us-east-1 `
  -ApiUrl "https://YOUR_API_GATEWAY_URL" `
  -BucketName "aws-inventory-dashboard-frontend-ACCOUNT_ID"
```

**Linux/Mac (Bash):**
```bash
cd scripts
chmod +x deploy-frontend-main-account.sh
./deploy-frontend-main-account.sh \
  --profile your-aws-profile \
  --region us-east-1 \
  --api-url "https://YOUR_API_GATEWAY_URL" \
  --bucket-name "aws-inventory-dashboard-frontend-ACCOUNT_ID"
```

### Step 4: Verify Frontend Deployment

1. **Check S3 bucket**
   ```bash
   aws s3 ls s3://aws-inventory-dashboard-frontend-ACCOUNT_ID/ --recursive
   ```

2. **Get CloudFront distribution**
   ```bash
   aws cloudformation describe-stacks \
     --stack-name aws-inventory-dashboard-frontend \
     --query "Stacks[0].Outputs[?OutputKey=='DistributionDomainName'].OutputValue" \
     --output text
   ```

3. **Test frontend accessibility**
   ```bash
   # Use the CloudFront domain name
   curl -I https://d12345abcdef.cloudfront.net
   ```
   Expected: HTTP 200 OK

4. **Invalidate CloudFront cache** (if updating)
   ```bash
   aws cloudfront create-invalidation \
     --distribution-id DISTRIBUTION_ID \
     --paths "/*"
   ```

### Step 5: Configure Custom Domain (Optional)

1. **Update Route53 DNS record**
   ```bash
   aws route53 change-resource-record-sets \
     --hosted-zone-id YOUR_ZONE_ID \
     --change-batch '{
       "Changes": [{
         "Action": "CREATE",
         "ResourceRecordSet": {
           "Name": "dashboard.example.com",
           "Type": "A",
           "AliasTarget": {
             "HostedZoneId": "Z2FDTNDATAQYW2",
             "DNSName": "d12345abcdef.cloudfront.net",
             "EvaluateTargetHealth": false
           }
         }
       }]
     }'
   ```

---

## Step-by-Step Cross-Account Role Setup

### Prerequisites
- Main account ID (from Step 1)
- List of member account IDs
- Access to each member account (via AWS credentials or AWS Organizations)

### Step 1: Identify Accounts to Configure

```bash
# List of member accounts that need InventoryReadRole
# Format: Account_ID Account_Name
# Example:
# 123456789012  sandbox-account
# 210987654321  production-account
# 345678901234  dev-account
```

### Step 2: Create Role in Each Member Account

For each member account, follow these steps:

#### Option A: Using Automated Script (Recommended)

1. **Switch to member account credentials**
   ```bash
   # Option 1: Configure profile
   aws configure --profile member-account
   
   # Option 2: Set environment variables
   export AWS_PROFILE=member-account
   
   # Option 3: Use temporary credentials
   export AWS_ACCESS_KEY_ID=YOUR_KEY
   export AWS_SECRET_ACCESS_KEY=YOUR_SECRET
   export AWS_SESSION_TOKEN=YOUR_TOKEN
   ```

2. **Verify you're in the correct account**
   ```bash
   aws sts get-caller-identity
   # Output should show the member account ID
   ```

3. **Run the setup script**
   ```bash
   # From project root
   cd scripts
   
   # Windows PowerShell
   .\setup-member-account.ps1
   
   # Linux/Mac Bash
   chmod +x setup-member-account.sh
   ./setup-member-account.sh
   ```

4. **Verify role creation**
   ```bash
   aws iam get-role --role-name InventoryReadRole \
     --query "Role.Arn" \
     --output text
   ```
   Expected output: `arn:aws:iam::MEMBER_ACCOUNT_ID:role/InventoryReadRole`

#### Option B: Manual CloudFormation Deployment

If the script fails, deploy manually using CloudFormation:

```bash
cd scripts

# Get the main account ID
MAIN_ACCOUNT_ID=YOUR_MAIN_ACCOUNT_ID

# Deploy the stack
aws cloudformation create-stack \
  --stack-name inventory-dashboard-member-role \
  --template-body file://../member-account-role.yaml \
  --parameters \
    ParameterKey=MainAccountId,ParameterValue=$MAIN_ACCOUNT_ID \
    ParameterKey=RoleName,ParameterValue=InventoryReadRole \
    ParameterKey=ExternalId,ParameterValue="optional-external-id" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

# Wait for stack to complete
aws cloudformation wait stack-create-complete \
  --stack-name inventory-dashboard-member-role
```

### Step 3: Verify Role Trust Relationship

From the member account, verify that the Lambda role in the main account can assume the role:

```bash
# View the role's trust policy
aws iam get-role --role-name InventoryReadRole

# The trust policy should allow the Lambda role from main account
# It should look like:
# {
#   "Version": "2012-10-17",
#   "Statement": [
#     {
#       "Effect": "Allow",
#       "Principal": {
#         "AWS": "arn:aws:iam::MAIN_ACCOUNT_ID:role/inventory-dashboard-RefreshFunctionRole-*"
#       },
#       "Action": "sts:AssumeRole"
#     }
#   ]
# }
```

### Step 4: Check Role Permissions

Verify the role has necessary permissions:

```bash
aws iam get-role-policy \
  --role-name InventoryReadRole \
  --policy-name InventoryReadPolicy \
  --query "RolePolicyDocument" | jq .
```

Expected policies should include read permissions for:
- EC2 (ec2:Describe*)
- S3 (s3:GetBucketLocation, s3:ListBucket)
- RDS (rds:DescribeDBInstances, rds:DescribeDBClusters)
- Other inventory services

### Step 5: Test Cross-Account Assumption (Optional)

From the main account, test if Lambda can assume the role:

```bash
# Get the Lambda role ARN
LAMBDA_ROLE_ARN=$(aws iam get-role \
  --role-name inventory-dashboard-RefreshFunctionRole-* \
  --query "Role.Arn" --output text | head -1)

# Attempt to assume member role from main account
aws sts assume-role \
  --role-arn arn:aws:iam::MEMBER_ACCOUNT_ID:role/InventoryReadRole \
  --role-session-name test-session
```

---

## Verification & Testing

### 1. Backend Verification

```bash
# Test Lambda function
aws lambda invoke \
  --function-name inventory-dashboard-RefreshFunction \
  --payload '{"service": "ec2"}' \
  /tmp/response.json

# Check response
cat /tmp/response.json | jq .
```

### 2. Frontend Verification

```bash
# Visit your CloudFront domain or custom domain in browser
curl -I https://your-domain.cloudfront.net

# Check if Cognito authentication works
# 1. Login with your credentials
# 2. Verify redirect back to dashboard
# 3. Check browser console for API calls
```

### 3. Multi-Account Inventory Collection

```bash
# Trigger inventory collection via Lambda
aws lambda invoke \
  --function-name inventory-dashboard-RefreshFunction \
  --payload '{"service": "ec2", "scope": "all"}' \
  /tmp/inventory.json

# Check DynamoDB for collected data
aws dynamodb scan \
  --table-name aws-inventory-data \
  --limit 10 \
  --output table
```

### 4. Check CloudWatch Logs

```bash
# View Lambda execution logs
aws logs tail /aws/lambda/inventory-dashboard-RefreshFunction --follow

# View API Gateway logs (if enabled)
aws logs tail /aws/apigateway/inventory-dashboard --follow

# View specific invocation logs
aws logs tail /aws/lambda/inventory-dashboard-RefreshFunction \
  --filter-pattern "ERROR|WARN" \
  --follow
```

---

## Troubleshooting

### Backend Issues

#### Lambda Function Not Deploying
```bash
# Check SAM build
sam validate --template backend/template.yaml

# Check dependencies
pip check

# View deployment events
aws cloudformation describe-stack-events \
  --stack-name inventory-dashboard \
  --query "StackEvents[0:10].{Resource:LogicalResourceId,Status:ResourceStatus,Reason:ResourceStatusReason}" \
  --output table
```

#### API Gateway 403 Forbidden
```bash
# Check Cognito configuration
aws cognito-idp describe-user-pool \
  --user-pool-id us-east-1_XXXXXXXXX \
  --query "UserPool.{Id:Id,Status:Status,CreationDate:CreationDate}"

# Verify API Gateway authorization
aws apigateway get-authorizers \
  --rest-api-id YOUR_API_ID
```

### Frontend Issues

#### CloudFront Returns 403
```bash
# Check S3 bucket policy
aws s3api get-bucket-policy --bucket aws-inventory-dashboard-frontend-ACCOUNT_ID

# Check bucket public access settings
aws s3api get-public-access-block \
  --bucket aws-inventory-dashboard-frontend-ACCOUNT_ID

# Invalidate CloudFront cache
aws cloudfront create-invalidation \
  --distribution-id YOUR_DISTRIBUTION_ID \
  --paths "/*"
```

#### CORS Errors in Browser
```bash
# Check API Gateway CORS configuration
aws apigateway get-stage \
  --rest-api-id YOUR_API_ID \
  --stage-name dev \
  --query "Stage.{MethodSettings:MethodSettings}" | jq .
```

### Cross-Account Role Issues

#### AccessDenied When Assuming Role
```bash
# Check role trust policy
aws iam get-role \
  --role-name InventoryReadRole \
  --query "Role.AssumeRolePolicyDocument" | jq .

# Verify Lambda role ARN
aws iam get-role \
  --role-name inventory-dashboard-RefreshFunctionRole-* \
  --query "Role.Arn"

# Test assumption
aws sts assume-role \
  --role-arn arn:aws:iam::MEMBER_ACCOUNT_ID:role/InventoryReadRole \
  --role-session-name test-session \
  --debug
```

#### Missing Permissions in Member Role
```bash
# Check role inline policies
aws iam list-role-policies --role-name InventoryReadRole

# Check each policy
aws iam get-role-policy \
  --role-name InventoryReadRole \
  --policy-name InventoryReadPolicy | jq .

# Compare with required permissions in IAM_POLICIES_AND_EXAMPLES.md
```

### General Debugging

```bash
# Enable debug logging for AWS CLI
export AWS_DEBUG=true

# Enable verbose output
aws cloudformation describe-stack-events \
  --stack-name inventory-dashboard \
  --debug 2>&1 | head -50

# Check AWS account limits
aws service-quotas list-service-quotas \
  --service-code lambda \
  --query "ServiceQuotas[?QuotaName=='Concurrent executions']"
```

---

## Rollback / Cleanup

### Delete Frontend Stack
```bash
aws cloudformation delete-stack \
  --stack-name aws-inventory-dashboard-frontend

# Wait for deletion
aws cloudformation wait stack-delete-complete \
  --stack-name aws-inventory-dashboard-frontend

# Clean up S3 bucket (if needed)
aws s3 rm s3://aws-inventory-dashboard-frontend-ACCOUNT_ID --recursive
```

### Delete Backend Stack
```bash
aws cloudformation delete-stack \
  --stack-name inventory-dashboard

aws cloudformation wait stack-delete-complete \
  --stack-name inventory-dashboard
```

### Delete Member Account Roles
```bash
# In each member account:
aws iam delete-role-policy \
  --role-name InventoryReadRole \
  --policy-name InventoryReadPolicy

aws iam delete-role \
  --role-name InventoryReadRole

# Or delete via CloudFormation if you created it that way:
aws cloudformation delete-stack \
  --stack-name inventory-dashboard-member-role
```

---

## Additional Resources

- [AWS SAM Documentation](https://docs.aws.amazon.com/serverless-application-model/)
- [Next.js Deployment Guide](https://nextjs.org/docs/deployment)
- [AWS IAM Cross-Account Access](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_common-scenarios_aws-accounts.html)
- [CloudFront Distribution Documentation](https://docs.aws.amazon.com/cloudfront/latest/developerguide/)
- [Cognito User Pool Documentation](https://docs.aws.amazon.com/cognito/latest/developerguide/)

---

## Quick Reference: Command Summary

### Deploy Everything
```bash
cd scripts
./deploy-all.sh --skip-confirmation  # Linux/Mac
.\deploy-all.ps1 -SkipConfirmation   # Windows
```

### Deploy Only Backend
```bash
cd scripts
./deploy-backend-main-account.sh --profile your-profile
.\deploy-backend-main-account.ps1 -Profile your-profile
```

### Deploy Only Frontend
```bash
cd scripts
./deploy-frontend-main-account.sh --api-url https://your-api-url
.\deploy-frontend-main-account.ps1 -ApiUrl https://your-api-url
```

### Setup Member Account
```bash
cd scripts
./setup-member-account.sh    # Linux/Mac
.\setup-member-account.ps1   # Windows
```

### View Logs
```bash
aws logs tail /aws/lambda/inventory-dashboard-RefreshFunction --follow
aws logs tail /aws/lambda/inventory-dashboard-ApiFunction --follow
```

### Get API URL
```bash
aws cloudformation describe-stacks \
  --stack-name inventory-dashboard \
  --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" \
  --output text
```

### Get CloudFront URL
```bash
aws cloudformation describe-stacks \
  --stack-name aws-inventory-dashboard-frontend \
  --query "Stacks[0].Outputs[?OutputKey=='DistributionDomainName'].OutputValue" \
  --output text
```

---

## Version History

- **v1.0.0** - Initial deployment guide created
  - Master deployment script with interactive setup
  - Step-by-step backend, frontend, and cross-account guides
  - Comprehensive troubleshooting section
