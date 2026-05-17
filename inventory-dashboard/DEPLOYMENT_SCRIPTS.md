# Platform-Specific Deployment Scripts

## Windows (PowerShell)

### Step 1: Backend Deployment

```powershell
# Navigate to scripts
cd scripts

# Run backend deployment
.\deploy-backend-main-account.ps1 `
  -Profile "your-aws-profile" `
  -Region "us-east-1" `
  -Environment "dev" `
  -StackName "inventory-dashboard" `
  -InventoryRoleName "InventoryReadRole" `
  -InventoryAccounts "123456789012:Account1,987654321098:Account2" `
  -CognitoUserPoolId "us-east-1_xxxxx" `
  -CognitoClientId "your-client-id" `
  -CognitoRegion "us-east-1"

# Save the API URL output
$ApiUrl = aws cloudformation describe-stacks `
  --stack-name inventory-dashboard `
  --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" `
  --output text
Write-Host "API URL: $ApiUrl"
```

### Step 2: Member Account Roles

```powershell
# For each member account, run:

$MemberAccountId = "123456789012"
$MainAccountId = "975678945875"
$LambdaRoleName = "arn:aws:iam::975678945875:role/InventoryFunctionRole"
$ExternalId = "your-external-id"

.\create-cross-account-role-complete.ps1 `
  -MemberAccountId $MemberAccountId `
  -MainAccountId $MainAccountId `
  -LambdaRoleName $LambdaRoleName `
  -ExternalId $ExternalId `
  -RoleName "InventoryReadRole"

# Verify
aws iam get-role --role-name InventoryReadRole
```

### Step 3: Frontend Deployment

```powershell
cd frontend

# Install dependencies
npm install

# Build
npm run build

# Create .env.local
$EnvContent = @"
NEXT_PUBLIC_API_URL=$ApiUrl
NEXT_PUBLIC_COGNITO_USER_POOL_ID=us-east-1_xxxxx
NEXT_PUBLIC_COGNITO_CLIENT_ID=your-client-id
NEXT_PUBLIC_COGNITO_REGION=us-east-1
NEXT_PUBLIC_COGNITO_DOMAIN=your-domain
"@
$EnvContent | Out-File -FilePath ".env.local" -Encoding UTF8

# Deploy using script
cd ../scripts
.\deploy-frontend-main-account.ps1 `
  -Profile "your-aws-profile" `
  -Region "us-east-1" `
  -BucketName "aws-inventory-dashboard-frontend-975678945875" `
  -FrontendStackName "aws-inventory-dashboard-frontend" `
  -ApiUrl $ApiUrl `
  -CognitoUserPoolId "us-east-1_xxxxx" `
  -CognitoClientId "your-client-id" `
  -CognitoRegion "us-east-1"
```

### Step 4: All-in-One Deployment

```powershell
cd scripts

# Full automated deployment
.\deploy-all.ps1 `
  -SkipConfirmation `
  -MainProfile "dcli_sharedsvcs2" `
  -MainAccountId "975678945875" `
  -Region "us-east-1" `
  -Environment "dev" `
  -BackendStack "inventory-dashboard" `
  -InventoryRoleName "InventoryReadRole" `
  -InventoryAccounts "529088296711:dcli_sandbox1,687360398174:dcli_sandbox2" `
  -CognitoUserPoolId "us-east-1_CiQtVfFnM" `
  -CognitoClientId "39v2nj1ueoajpeqfrckpthd0go" `
  -CognitoRegion "us-east-1" `
  -BucketName "aws-inventory-dashboard-frontend-975678945875" `
  -FrontendStack "aws-inventory-dashboard-frontend"
```

### Windows Verification

```powershell
# Check backend
aws cloudformation describe-stacks `
  --stack-name inventory-dashboard `
  --query "Stacks[0].StackStatus"

# Check frontend
aws cloudformation describe-stacks `
  --stack-name aws-inventory-dashboard-frontend `
  --query "Stacks[0].StackStatus"

# View outputs
aws cloudformation describe-stacks `
  --stack-name inventory-dashboard `
  --query "Stacks[0].Outputs" `
  --output table

# Get CloudFront URL
aws cloudformation describe-stacks `
  --stack-name aws-inventory-dashboard-frontend `
  --query "Stacks[0].Outputs[?OutputKey=='CloudFrontUrl'].OutputValue" `
  --output text
```

### Windows Cleanup

```powershell
# Delete frontend
aws cloudformation delete-stack `
  --stack-name aws-inventory-dashboard-frontend

# Delete backend
aws cloudformation delete-stack `
  --stack-name inventory-dashboard

# Delete member account role
aws iam delete-role-policy `
  --role-name InventoryReadRole `
  --policy-name InventoryReadPolicy

aws iam delete-role `
  --role-name InventoryReadRole
```

---

## Linux / macOS (Bash)

### Step 1: Backend Deployment

```bash
# Navigate to scripts
cd scripts

# Make scripts executable
chmod +x deploy-backend-main-account.sh
chmod +x deploy-frontend-main-account.sh
chmod +x create-cross-account-role-complete.sh
chmod +x deploy-all.sh

# Run backend deployment
./deploy-backend-main-account.sh \
  --profile "your-aws-profile" \
  --region "us-east-1" \
  --environment "dev" \
  --stack-name "inventory-dashboard" \
  --inventory-role-name "InventoryReadRole" \
  --inventory-accounts "123456789012:Account1,987654321098:Account2" \
  --cognito-user-pool-id "us-east-1_xxxxx" \
  --cognito-client-id "your-client-id" \
  --cognito-region "us-east-1"

# Save the API URL output
export API_URL=$(aws cloudformation describe-stacks \
  --stack-name inventory-dashboard \
  --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" \
  --output text)
echo "API URL: $API_URL"
```

### Step 2: Member Account Roles

```bash
# For each member account, run:

MEMBER_ACCOUNT_ID="123456789012"
MAIN_ACCOUNT_ID="975678945875"
LAMBDA_ROLE_NAME="arn:aws:iam::975678945875:role/InventoryFunctionRole"
EXTERNAL_ID="your-external-id"
ROLE_NAME="InventoryReadRole"

./create-cross-account-role-complete.sh \
  "$MEMBER_ACCOUNT_ID" \
  "$MAIN_ACCOUNT_ID" \
  "$LAMBDA_ROLE_NAME" \
  "$EXTERNAL_ID" \
  "$ROLE_NAME"

# Verify
aws iam get-role --role-name InventoryReadRole
```

### Step 3: Frontend Deployment

```bash
cd frontend

# Install dependencies
npm install

# Build
npm run build

# Create .env.local
cat > .env.local <<EOF
NEXT_PUBLIC_API_URL=${API_URL}
NEXT_PUBLIC_COGNITO_USER_POOL_ID=us-east-1_xxxxx
NEXT_PUBLIC_COGNITO_CLIENT_ID=your-client-id
NEXT_PUBLIC_COGNITO_REGION=us-east-1
NEXT_PUBLIC_COGNITO_DOMAIN=your-domain
EOF

# Deploy using script
cd ../scripts
./deploy-frontend-main-account.sh \
  --profile "your-aws-profile" \
  --region "us-east-1" \
  --bucket-name "aws-inventory-dashboard-frontend-975678945875" \
  --frontend-stack-name "aws-inventory-dashboard-frontend" \
  --api-url "$API_URL" \
  --cognito-user-pool-id "us-east-1_xxxxx" \
  --cognito-client-id "your-client-id" \
  --cognito-region "us-east-1"
```

### Step 4: All-in-One Deployment

```bash
cd scripts

# Full automated deployment
./deploy-all.sh \
  --skip-confirmation \
  --main-profile "dcli_sharedsvcs2" \
  --main-account-id "975678945875" \
  --region "us-east-1" \
  --environment "dev" \
  --backend-stack "inventory-dashboard" \
  --inventory-role-name "InventoryReadRole" \
  --inventory-accounts "529088296711:dcli_sandbox1,687360398174:dcli_sandbox2" \
  --cognito-user-pool-id "us-east-1_CiQtVfFnM" \
  --cognito-client-id "39v2nj1ueoajpeqfrckpthd0go" \
  --cognito-region "us-east-1" \
  --bucket-name "aws-inventory-dashboard-frontend-975678945875" \
  --frontend-stack "aws-inventory-dashboard-frontend"
```

### Linux/macOS Verification

```bash
# Check backend
aws cloudformation describe-stacks \
  --stack-name inventory-dashboard \
  --query "Stacks[0].StackStatus" \
  --output text

# Check frontend
aws cloudformation describe-stacks \
  --stack-name aws-inventory-dashboard-frontend \
  --query "Stacks[0].StackStatus" \
  --output text

# View outputs
aws cloudformation describe-stacks \
  --stack-name inventory-dashboard \
  --query "Stacks[0].Outputs" \
  --output table

# Get CloudFront URL
aws cloudformation describe-stacks \
  --stack-name aws-inventory-dashboard-frontend \
  --query "Stacks[0].Outputs[?OutputKey=='CloudFrontUrl'].OutputValue" \
  --output text | xargs echo "Frontend URL:"
```

### Linux/macOS Cleanup

```bash
# Delete frontend
aws cloudformation delete-stack \
  --stack-name aws-inventory-dashboard-frontend

# Delete backend
aws cloudformation delete-stack \
  --stack-name inventory-dashboard

# Delete member account role
aws iam delete-role-policy \
  --role-name InventoryReadRole \
  --policy-name InventoryReadPolicy

aws iam delete-role \
  --role-name InventoryReadRole
```

---

## Cross-Platform Commands

### Prerequisites Verification (Works on all platforms)

```bash
# Check AWS CLI
aws --version

# Check SAM CLI
sam --version

# Check Node.js
node --version
npm --version

# Check Python
python --version
python3 --version

# Configure AWS credentials
aws configure

# List AWS profiles
aws configure list-profiles
```

### Environment Setup

#### Windows PowerShell
```powershell
# Set AWS profile for current session
$env:AWS_PROFILE = "your-profile"

# View AWS profile
$env:AWS_PROFILE

# View AWS region
$env:AWS_REGION

# View AWS credentials location
$env:USERPROFILE\.aws\credentials
```

#### Linux/macOS Bash
```bash
# Set AWS profile for current session
export AWS_PROFILE=your-profile

# View AWS profile
echo $AWS_PROFILE

# View AWS region
echo $AWS_REGION

# View AWS credentials location
cat ~/.aws/credentials
```

### Test AWS Credentials

```bash
# Both platforms
aws sts get-caller-identity

# Expected output:
# {
#     "UserId": "AIDAI...",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/username"
# }
```

---

## Troubleshooting Command Syntax

### PowerShell Issues

```powershell
# If getting "cannot be loaded because running scripts is disabled"
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# If getting "permission denied"
# Right-click PowerShell → Run as Administrator

# If getting "script not found"
# Ensure you're in the scripts directory
Get-Location
ls

# Debug script
$DebugPreference = "Continue"
.\deploy-all.ps1 -Debug
```

### Bash Issues

```bash
# If getting "permission denied"
chmod +x deploy-all.sh

# If getting "command not found"
# Ensure you're in the scripts directory
pwd
ls -la

# If script uses Windows line endings
dos2unix deploy-all.sh
# OR
sed -i 's/\r$//' deploy-all.sh

# Debug script
bash -x deploy-all.sh
# OR
set -x
./deploy-all.sh
```

---

## Script Parameters

### Backend Script Parameters

| Parameter | Value | Example |
|-----------|-------|---------|
| --profile | AWS profile name | your-aws-profile |
| --region | AWS region | us-east-1 |
| --environment | dev/prod | dev |
| --stack-name | CloudFormation stack name | inventory-dashboard |
| --inventory-role-name | IAM role name | InventoryReadRole |
| --inventory-accounts | Comma-separated accounts | "123456789012:Prod,987654321098:Dev" |
| --cognito-user-pool-id | Cognito pool ID | us-east-1_xxxxx |
| --cognito-client-id | Cognito client ID | abcd1234xyz |
| --cognito-region | Cognito region | us-east-1 |
| --skip-confirmation | No user prompts | (flag) |

### Frontend Script Parameters

| Parameter | Value | Example |
|-----------|-------|---------|
| --profile | AWS profile name | your-aws-profile |
| --region | AWS region | us-east-1 |
| --bucket-name | S3 bucket name | aws-inventory-frontend-123456789012 |
| --frontend-stack-name | CloudFormation stack | aws-inventory-dashboard-frontend |
| --api-url | Backend API URL | https://xxx.execute-api.us-east-1.amazonaws.com/dev |
| --cognito-user-pool-id | Cognito pool ID | us-east-1_xxxxx |
| --cognito-client-id | Cognito client ID | abcd1234xyz |
| --cognito-region | Cognito region | us-east-1 |
| --cognito-domain | Cognito domain | my-domain |
| --skip-build | Skip npm build | (flag) |

---

## Expected Output Examples

### Successful Backend Deployment

```
Build Succeeded

✓ Waiting for stack create/update to complete

Successfully created/updated stack in cloudformation


CloudFormation outputs:
╔════════════════════╦════════════════════════════════╗
║ Stack Output       ║ Value                          ║
╠════════════════════╬════════════════════════════════╣
║ ApiUrl             ║ https://xxx.execute-api...     ║
║ LambdaFunctionName  ║ inventory-dashboard-RefreshF...║
║ DynamoDBTableName   ║ inventory-dashboard-resources  ║
╚════════════════════╩════════════════════════════════╝
```

### Successful Frontend Deployment

```
✓ Compiled successfully
✓ Linting and checking validity of types
✓ Collecting page data
✓ Generating static pages

Next.js build output: .next/
Static files: public/

✓ Frontend deployed to S3
✓ CloudFront cache invalidated

CloudFront URL: https://d123abc.cloudfront.net
```

### Successful Role Creation

```
✓ Creating trust policy
✓ IAM role created
✓ Permissions policy attached

Role ARN: arn:aws:iam::123456789012:role/InventoryReadRole
✓ Role ready for cross-account access
```

---

## Time Estimates

| Phase | Windows | Linux/macOS |
|-------|---------|------------|
| Backend | 5-10 min | 5-10 min |
| Member Role | 2-3 min | 2-3 min |
| Frontend | 3-5 min | 3-5 min |
| **Total** | **10-18 min** | **10-18 min** |

---

## Support

For issues with specific scripts, check:
- [DEPLOYMENT_GUIDE.md](../DEPLOYMENT_GUIDE.md) - Full documentation
- [MULTI_ACCOUNT_SETUP.md](../MULTI_ACCOUNT_SETUP.md) - Multi-account details
- Log files in `~/.aws/` or `$env:USERPROFILE\.aws\`
