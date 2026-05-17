# Quick Deployment Commands

## Prerequisites Check

```bash
# Verify all required tools are installed
aws --version
sam --version
node --version
npm --version
python --version
```

---

## Quick Start (Automated - Recommended)

```bash
cd scripts

# Full deployment (all steps)
./deploy-all.sh --skip-confirmation

# Or Windows PowerShell
.\deploy-all.ps1 -SkipConfirmation
```

---

## Phase-by-Phase Deployment

### PHASE 1: Backend (Lambda + API Gateway + DynamoDB)

```bash
# Option A: Using Script
cd scripts
./deploy-backend-main-account.sh \
  --profile YOUR_AWS_PROFILE \
  --region us-east-1 \
  --environment dev

# Option B: Manual
cd backend
sam build
sam deploy --guided
```

**Save API URL:**
```bash
API_URL=$(aws cloudformation describe-stacks \
  --stack-name inventory-dashboard \
  --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" \
  --output text)
echo $API_URL
```

---

### PHASE 2: Member Account Roles

**Switch to each member account first:**
```bash
export AWS_PROFILE=member-account-profile
```

**Create role in member account:**
```bash
cd scripts

# Option A: Using Script
./create-cross-account-role-complete.sh \
  MEMBER_ACCOUNT_ID \
  MAIN_ACCOUNT_ID \
  "LAMBDA_ROLE_NAME" \
  "optional-external-id"

# Option B: Using CloudFormation
aws cloudformation create-stack \
  --stack-name inventory-read-role \
  --template-body file://member-account-role.yaml \
  --parameters \
    ParameterKey=MainAccountId,ParameterValue=MAIN_ACCOUNT_ID \
  --capabilities CAPABILITY_NAMED_IAM
```

**Repeat for each member account**

---

### PHASE 3: Frontend (S3 + CloudFront)

```bash
# Back to main account
export AWS_PROFILE=main-account-profile

# Build frontend
cd frontend
npm install
npm run build

# Deploy using script
cd ../scripts
./deploy-frontend-main-account.sh \
  --api-url "YOUR_API_URL" \
  --profile YOUR_AWS_PROFILE

# Or manual deployment
cd ../frontend
aws s3 sync out/ s3://your-bucket-name/ --delete
aws cloudformation update-stack \
  --stack-name aws-inventory-dashboard-frontend \
  --template-body file://frontend-infrastructure.yaml
```

---

## Verification

```bash
# 1. Check backend status
aws cloudformation describe-stacks \
  --stack-name inventory-dashboard \
  --query "Stacks[0].StackStatus"

# 2. Check Lambda function
aws lambda list-functions --query "Functions[?contains(FunctionName, 'inventory')].FunctionName"

# 3. Check member account role
aws iam get-role --role-name InventoryReadRole

# 4. Test API
curl -X GET "YOUR_API_URL/health"

# 5. Get frontend URL
aws cloudformation describe-stacks \
  --stack-name aws-inventory-dashboard-frontend \
  --query "Stacks[0].Outputs"
```

---

## Updates & Rollback

### Update Backend
```bash
cd backend
sam build
sam deploy --guided
```

### Update Frontend
```bash
cd frontend
npm run build

# Invalidate CloudFront cache
DIST_ID=$(aws cloudformation describe-stacks \
  --stack-name aws-inventory-dashboard-frontend \
  --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDistributionId'].OutputValue" \
  --output text)

aws cloudfront create-invalidation --distribution-id $DIST_ID --paths "/*"
```

### Rollback Backend
```bash
aws cloudformation cancel-update-stack \
  --stack-name inventory-dashboard
```

---

## Cleanup (Delete Everything)

```bash
# 1. Delete frontend stack
aws cloudformation delete-stack \
  --stack-name aws-inventory-dashboard-frontend

# 2. Delete backend stack
aws cloudformation delete-stack \
  --stack-name inventory-dashboard

# 3. Delete member account roles (in each member account)
aws iam delete-role-policy \
  --role-name InventoryReadRole \
  --policy-name InventoryReadPolicy

aws iam delete-role \
  --role-name InventoryReadRole

# 4. Delete S3 buckets (if empty)
aws s3 rb s3://your-bucket-name
```

---

## Troubleshooting Commands

```bash
# Check credentials
aws sts get-caller-identity

# Check CloudFormation stack events
aws cloudformation describe-stack-events \
  --stack-name inventory-dashboard

# View Lambda logs
aws logs tail /aws/lambda/inventory-dashboard-RefreshFunction --follow

# Test role assumption
aws sts assume-role \
  --role-arn arn:aws:iam::MEMBER_ID:role/InventoryReadRole \
  --role-session-name test

# List all resources in stack
aws cloudformation describe-stack-resources \
  --stack-name inventory-dashboard

# Check Lambda configuration
aws lambda get-function-configuration \
  --function-name inventory-dashboard-RefreshFunction
```

---

## Environment Variables Reference

**For Backend (.env or samconfig.toml):**
- `INVENTORY_ACCOUNTS` - Comma-separated accounts (format: id1:name1,id2:name2)
- `INVENTORY_ROLE_NAME` - Name of cross-account role (default: InventoryReadRole)
- `EXTERNAL_ID` - Optional security parameter for assume role

**For Frontend (.env.local):**
```env
NEXT_PUBLIC_API_URL=https://your-api-endpoint
NEXT_PUBLIC_COGNITO_USER_POOL_ID=us-east-1_xxxxx
NEXT_PUBLIC_COGNITO_CLIENT_ID=your-client-id
NEXT_PUBLIC_COGNITO_REGION=us-east-1
NEXT_PUBLIC_COGNITO_DOMAIN=your-domain
```

---

## File Locations

```
project-root/
├── backend/
│   ├── template.yaml          (SAM template)
│   ├── samconfig.toml         (SAM configuration)
│   ├── src/app.py             (Lambda handler)
│   └── requirements.txt       (Python dependencies)
├── frontend/
│   ├── next.config.js         (Next.js configuration)
│   ├── .env.local            (Environment variables)
│   ├── frontend-infrastructure.yaml (CloudFormation)
│   └── package.json          (Node dependencies)
├── scripts/
│   ├── deploy-all.sh                    (Master script)
│   ├── deploy-backend-main-account.sh   (Backend)
│   ├── deploy-frontend-main-account.sh  (Frontend)
│   ├── create-cross-account-role-complete.sh (Member roles)
│   └── policies/
│       └── inventory-read-policy.json   (IAM policy)
├── member-account-role.yaml    (CloudFormation for member account)
└── DEPLOYMENT_INSTRUCTIONS.md  (Full guide - you are here!)
```

---

## Common Scenarios

### Deploy Everything from Scratch
```bash
cd scripts
./deploy-all.sh --skip-confirmation
```

### Update Only the Backend
```bash
cd backend && sam build && sam deploy
```

### Update Only the Frontend
```bash
cd frontend && npm run build
cd ../scripts && ./deploy-frontend-main-account.sh --api-url YOUR_API_URL
```

### Add a New Member Account
```bash
cd scripts
./create-cross-account-role-complete.sh NEW_ACCOUNT_ID MAIN_ACCOUNT_ID
```

### Check Deployment Status
```bash
aws cloudformation describe-stacks --stack-name inventory-dashboard --query "Stacks[0].[StackStatus,CreationTime]"
```

### View All Deployment Outputs
```bash
aws cloudformation describe-stacks \
  --stack-name inventory-dashboard \
  --query "Stacks[0].Outputs" --output table

aws cloudformation describe-stacks \
  --stack-name aws-inventory-dashboard-frontend \
  --query "Stacks[0].Outputs" --output table
```

---

## Next Steps After Deployment

1. ✅ Access frontend via CloudFront URL
2. ✅ Login with Cognito credentials
3. ✅ Verify inventory data loads
4. ✅ Test cross-account resource viewing
5. ✅ Configure auto-refresh schedule
6. ✅ Set up CloudWatch alarms
7. ✅ Enable CloudFront access logs
8. ✅ Document API endpoints for custom integrations

---

## Support & Documentation

- Full guide: [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)
- Multi-account setup: [MULTI_ACCOUNT_SETUP.md](MULTI_ACCOUNT_SETUP.md)
- Frontend deployment: [frontend/FRONTEND_DEPLOYMENT.md](frontend/FRONTEND_DEPLOYMENT.md)
- Troubleshooting: [DEPLOYMENT_GUIDE.md#troubleshooting](DEPLOYMENT_GUIDE.md)
