# AWS Inventory Dashboard — Deployment Guide

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Environment Reference](#environment-reference)
4. [Step 1 — Cross-Account IAM Roles (Member Accounts)](#step-1--cross-account-iam-roles-member-accounts)
5. [Step 2 — Backend Deployment (SAM)](#step-2--backend-deployment-sam)
6. [Step 3 — Frontend Deployment (S3 + CloudFront)](#step-3--frontend-deployment-s3--cloudfront)
7. [Step 4 — Post-Deployment Verification](#step-4--post-deployment-verification)
8. [Adding a New Member Account](#adding-a-new-member-account)
9. [Re-deploying After Code Changes](#re-deploying-after-code-changes)
10. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
Browser
  └─► CloudFront (status.aws.dcli.com)
        └─► S3 (static Next.js export)
              └─► API Gateway (prod stage, Cognito JWT auth)
                    └─► Lambda InventoryFunction  ──► DynamoDB (inventory + metadata tables)
                    └─► Lambda RefreshFunction    ──► STS AssumeRole ──► Member Accounts
                                                                            ├─ ec2 / vpc / eks / ecs
                                                                            ├─ s3 / rds / dynamodb
                                                                            ├─ iam / lambda
                                                                            └─ (us-east-1, us-east-2)
```

**Auth flow**: Browser → Cognito Hosted UI (SAML/OAuth2) → `/auth/callback?code=` → token stored in `localStorage` → `Authorization: Bearer <idToken>` on every API request → API Gateway Cognito authorizer validates JWT → Lambda.

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| AWS CLI | v2 | https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html |
| AWS SAM CLI | ≥ 1.100 | https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html |
| Node.js | 18+ | https://nodejs.org |
| Python | 3.12 | https://www.python.org |
| pip | latest | bundled with Python |

```bash
# Verify
aws --version
sam --version
node --version
python3 --version
```

### AWS Profiles

```
~/.aws/credentials (or SSO config)

[dcli_sharedsvcs2]   # Main account — 975678945875
[dcli_sandbox1]      # Member account — 529088296711
[dcli_sandbox2]      # Member account — 687360398174
```

Verify access:

```bash
aws sts get-caller-identity --profile dcli_sharedsvcs2
# Expected: Account "975678945875"
```

---

## Environment Reference

### Current Infrastructure

| Resource | Value |
|----------|-------|
| Main AWS Account | `975678945875` (dcli-sharedsvcs2) |
| Backend Region | `us-east-1` |
| Frontend Region | `us-east-2` |
| SAM Stack Name | `inventory-dashboard` |
| InventoryFunction | `inventory-dashboard-InventoryFunction-dIyVdcG9NMS9` |
| RefreshFunction | `inventory-dashboard-RefreshFunction-ZP5pOYnIOIgM` |
| Lambda Execution Role | `inventory-dashboard-InventoryFunctionRole-QXNabHTvrDtL` |
| API Gateway URL | `https://1zhuxjq9s6.execute-api.us-east-1.amazonaws.com/prod` |
| API Gateway Stage | `dev` |
| DynamoDB Inventory Table | `aws-inventory-data-dev` (us-east-1) |
| DynamoDB Metadata Table | `aws-inventory-metadata-dev` (us-east-1) |
| Cognito User Pool | `us-east-2_Cb4IW3we4` (us-east-2, account 307946672793) |
| Cognito Client ID | `776457erti67mcbdlffj8idon6` |
| Cognito Domain | `us-east-2cb4iw3we4.auth.us-east-2.amazoncognito.com` |
| Cognito Callback URL | `https://status.aws.dcli.com/auth/callback` (no trailing slash) |
| S3 Frontend Bucket | `dcli-inventory-dashboard-frontend` (us-east-2) |
| CloudFront Distribution | `E3REYNS02TTB3V` |
| CloudFront Domain | `status.aws.dcli.com` |
| WAF ACL | `inventory-dashboard-dev-web-acl` |
| Allowed Regions | `us-east-1`, `us-east-2` |
| Member Accounts | `529088296711` (dcli_sandbox1), `687360398174` (dcli_sandbox2) |
| Cross-account Role Name | `InventoryReadRole` |

### Lambda Environment Variables

Both `InventoryFunction` and `RefreshFunction` share these variables (set via AWS Console or `aws lambda update-function-configuration`):

```
ALLOWED_REGIONS            = us-east-1,us-east-2
COGNITO_CLIENT_ID          = 776457erti67mcbdlffj8idon6
COGNITO_DOMAIN             = status.aws.dcli.com
COGNITO_REGION             = us-east-2
COGNITO_USER_POOL_ID       = us-east-2_Cb4IW3we4
INVENTORY_ACCOUNTS         = 975678945875:dcli-sharedsvcs2,529088296711:dcli_sandbox1,687360398174:dcli_sandbox2
INVENTORY_TABLE_NAME       = aws-inventory-data-dev
METADATA_TABLE_NAME        = aws-inventory-metadata-dev
```

`InventoryFunction` only:
```
REFRESH_FUNCTION_NAME      = inventory-dashboard-RefreshFunction-ZP5pOYnIOIgM
```

---

## Step 1 — Cross-Account IAM Roles (Member Accounts)

Run this once per member account. It deploys the `InventoryReadRole` IAM role that allows the main account's Lambda to `AssumeRole` and read resources.

### Using the Script

```bash
cd scripts/

# Linux / macOS — authenticate to the TARGET member account first, then run:
chmod +x setup-member-account.sh
./setup-member-account.sh

# Windows PowerShell
.\setup-member-account.ps1
```

### Using CloudFormation Directly

```bash
# Set variables
MAIN_ACCOUNT_ID=975678945875
LAMBDA_ROLE=inventory-dashboard-InventoryFunctionRole-QXNabHTvrDtL
MEMBER_PROFILE=dcli_sandbox1   # change per account

# Deploy
aws cloudformation deploy \
  --template-file member-account-role.yaml \
  --stack-name inventory-dashboard-member-role \
  --region us-east-1 \
  --profile ${MEMBER_PROFILE} \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    MainAccountId=${MAIN_ACCOUNT_ID} \
    LambdaExecutionRoleName=${LAMBDA_ROLE} \
    RoleName=InventoryReadRole \
    ExternalId=""

# Confirm role ARN
aws cloudformation describe-stacks \
  --stack-name inventory-dashboard-member-role \
  --region us-east-1 \
  --profile ${MEMBER_PROFILE} \
  --query 'Stacks[0].Outputs' \
  --output table
```

### Verify the Role

After deploying, verify the trust policy from the **main** account:

```bash
aws iam get-role \
  --role-name InventoryReadRole \
  --profile ${MEMBER_PROFILE} \
  --query 'Role.AssumeRolePolicyDocument'
```

The principal should be:
```
arn:aws:iam::975678945875:role/inventory-dashboard-InventoryFunctionRole-QXNabHTvrDtL
```

---

## Step 2 — Backend Deployment (SAM)

### 2a. First-Time Deploy

```bash
cd backend/

# 1. Install Python layer dependencies
chmod +x setup_layer.sh
./setup_layer.sh
# Or manually:
# pip install -r requirements.txt -t layer/python/lib/python3.12/site-packages/

# 2. Build SAM application
sam build

# 3. Deploy (guided — saves answers to samconfig.toml)
sam deploy --guided \
  --profile dcli_sharedsvcs2 \
  --region us-east-1

# When prompted, use these values:
#   Stack Name:              inventory-dashboard
#   AWS Region:              us-east-1
#   Environment:             dev
#   ExternalId:              (leave blank)
#   InventoryRoleName:       InventoryReadRole
#   ExistingCognitoUserPoolId: us-east-2_Cb4IW3we4
#   ExistingCognitoClientId: 776457erti67mcbdlffj8idon6
#   CognitoRegion:           us-east-2
#   InventoryAccounts:       975678945875:dcli-sharedsvcs2,529088296711:dcli_sandbox1,687360398174:dcli_sandbox2
#   Save to samconfig.toml:  Y
```

### 2b. Re-deploy After Template or Dependency Changes

```bash
cd backend/

sam build && sam deploy --profile dcli_sharedsvcs2
```

### 2c. Quick Code-Only Patch (Faster — No SAM Required)

Use when only `.py` files under `src/` changed (no new pip dependencies, no `template.yaml` changes):

```bash
cd backend/

# Package all source files
rm -rf /tmp/lambda-package && mkdir /tmp/lambda-package
cp -r src/* /tmp/lambda-package/
cd /tmp/lambda-package && zip -r /tmp/lambda-full.zip . -q
cd -

# Deploy InventoryFunction
aws lambda update-function-code \
  --function-name inventory-dashboard-InventoryFunction-dIyVdcG9NMS9 \
  --region us-east-1 \
  --profile dcli_sharedsvcs2 \
  --zip-file fileb:///tmp/lambda-full.zip \
  --query 'LastModified' --output text

# Deploy RefreshFunction
aws lambda update-function-code \
  --function-name inventory-dashboard-RefreshFunction-ZP5pOYnIOIgM \
  --region us-east-1 \
  --profile dcli_sharedsvcs2 \
  --zip-file fileb:///tmp/lambda-full.zip \
  --query 'LastModified' --output text
```

### 2d. Update Lambda Environment Variables

```bash
# Update both functions with current variable set (replace INVENTORY_ACCOUNTS if adding accounts)
for FUNC in \
  inventory-dashboard-InventoryFunction-dIyVdcG9NMS9 \
  inventory-dashboard-RefreshFunction-ZP5pOYnIOIgM; do
  aws lambda update-function-configuration \
    --function-name ${FUNC} \
    --region us-east-1 \
    --profile dcli_sharedsvcs2 \
    --environment '{"Variables":{
      "ALLOWED_REGIONS":"us-east-1,us-east-2",
      "COGNITO_CLIENT_ID":"776457erti67mcbdlffj8idon6",
      "COGNITO_DOMAIN":"status.aws.dcli.com",
      "COGNITO_REGION":"us-east-2",
      "COGNITO_USER_POOL_ID":"us-east-2_Cb4IW3we4",
      "INVENTORY_ACCOUNTS":"975678945875:dcli-sharedsvcs2,529088296711:dcli_sandbox1,687360398174:dcli_sandbox2",
      "INVENTORY_TABLE_NAME":"aws-inventory-data-dev",
      "METADATA_TABLE_NAME":"aws-inventory-metadata-dev",
      "REFRESH_FUNCTION_NAME":"inventory-dashboard-RefreshFunction-ZP5pOYnIOIgM"
    }}' \
    --query 'LastModified' --output text
  echo "Updated ${FUNC}"
done
```

> **Note**: `REFRESH_FUNCTION_NAME` is only used by `InventoryFunction`. It is harmless to set it on both.

### 2e. Trigger Data Collection

After any backend deploy, trigger a full refresh to populate DynamoDB:

```bash
aws lambda invoke \
  --function-name inventory-dashboard-RefreshFunction-ZP5pOYnIOIgM \
  --region us-east-1 \
  --profile dcli_sharedsvcs2 \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/refresh-result.json

python3 -c "
import json
with open('/tmp/refresh-result.json') as f:
    r = json.load(f)
body = json.loads(r['body'])
print('Status:', 'OK' if r.get('StatusCode') == 200 else 'ERROR')
print('Total resources:', body.get('totalResources', 0))
from collections import defaultdict
totals = defaultdict(int)
for res in body.get('results', []):
    totals[res['service']] += res['resourceCount']
for svc, n in sorted(totals.items()):
    print(f'  {svc}: {n}')
"
```

---

## Step 3 — Frontend Deployment (S3 + CloudFront)

### 3a. Environment File

Create or verify `frontend/.env` before building. These variables are **baked into the JavaScript bundle at build time** — any change requires a full rebuild.

```bash
cat > frontend/.env << 'EOF'
NEXT_PUBLIC_API_URL=https://1zhuxjq9s6.execute-api.us-east-1.amazonaws.com/prod
NEXT_PUBLIC_COGNITO_USER_POOL_ID=us-east-2_Cb4IW3we4
NEXT_PUBLIC_COGNITO_CLIENT_ID=776457erti67mcbdlffj8idon6
NEXT_PUBLIC_COGNITO_REGION=us-east-2
NEXT_PUBLIC_COGNITO_DOMAIN=us-east-2cb4iw3we4
EOF
```

### 3b. Install Dependencies

```bash
cd frontend/
npm ci
```

### 3c. Build

```bash
cd frontend/
npm run build
# Outputs static files to ./out/
```

Build requirements verified in `next.config.js`:
- `output: 'export'` — static export mode
- `trailingSlash: false` — **required**: prevents S3 from stripping `?code=` on the OAuth callback
- `optimizeCss: false` — required (no `critters` dependency)
- `images.unoptimized: true` — required for static export

### 3d. Deploy to S3

```bash
cd frontend/

# Static assets (JS, CSS, images) — long-lived cache
aws s3 sync out/ s3://dcli-inventory-dashboard-frontend \
  --profile dcli_sharedsvcs2 \
  --region us-east-2 \
  --delete \
  --exclude "*.html" \
  --exclude "*.json" \
  --cache-control "public, max-age=31536000, immutable"

# HTML and JSON — never cache (must always be fresh)
aws s3 sync out/ s3://dcli-inventory-dashboard-frontend \
  --profile dcli_sharedsvcs2 \
  --region us-east-2 \
  --include "*.html" \
  --include "*.json" \
  --cache-control "no-cache, no-store, must-revalidate"
```

### 3e. Invalidate CloudFront Cache

Must be run after every S3 sync, otherwise CloudFront serves stale files.

```bash
aws cloudfront create-invalidation \
  --distribution-id E3REYNS02TTB3V \
  --paths "/*" \
  --profile dcli_sharedsvcs2 \
  --query 'Invalidation.{Id:Id,Status:Status}' \
  --output table
```

Invalidation takes 1–3 minutes. Check status:

```bash
# Replace INVALIDATION_ID with the Id from the previous output
aws cloudfront get-invalidation \
  --distribution-id E3REYNS02TTB3V \
  --id <INVALIDATION_ID> \
  --profile dcli_sharedsvcs2 \
  --query 'Invalidation.Status' \
  --output text
```

### 3f. One-liner Full Frontend Deploy

```bash
cd frontend && \
npm run build && \
aws s3 sync out/ s3://dcli-inventory-dashboard-frontend \
  --profile dcli_sharedsvcs2 --region us-east-2 \
  --delete --exclude "*.html" --exclude "*.json" \
  --cache-control "public, max-age=31536000, immutable" && \
aws s3 sync out/ s3://dcli-inventory-dashboard-frontend \
  --profile dcli_sharedsvcs2 --region us-east-2 \
  --include "*.html" --include "*.json" \
  --cache-control "no-cache, no-store, must-revalidate" && \
aws cloudfront create-invalidation \
  --distribution-id E3REYNS02TTB3V --paths "/*" \
  --profile dcli_sharedsvcs2 \
  --query 'Invalidation.Id' --output text
```

---

## Step 4 — Post-Deployment Verification

### 4a. API Gateway Health

```bash
# Test that the API returns 401 (not 403 or 5xx) for unauthenticated requests
curl -s -o /dev/null -w "%{http_code}" \
  "https://1zhuxjq9s6.execute-api.us-east-1.amazonaws.com/prod/inventory?service=ec2"
# Expected: 401
```

### 4b. CloudFront Serves JS Correctly

```bash
# Check that JS chunks return correct content-type (not text/html)
curl -sI "https://status.aws.dcli.com/_next/static/chunks/main.js" \
  | grep -i "content-type"
# Expected: content-type: text/javascript
```

### 4c. Auth Callback (No Redirect)

```bash
# Verify the callback URL returns 200 (not 302 redirect that would strip ?code=)
curl -sI "https://status.aws.dcli.com/auth/callback" \
  | grep -i "HTTP\|location"
# Expected: HTTP/2 200 (no Location header)
```

### 4d. DynamoDB Data

```bash
# Verify data exists per service
for SERVICE in ec2 s3 iam rds lambda vpc eks ecs dynamodb; do
  COUNT=$(aws dynamodb query \
    --table-name aws-inventory-data-dev \
    --region us-east-1 \
    --profile dcli_sharedsvcs2 \
    --key-condition-expression "pk = :pk" \
    --expression-attribute-values "{\":pk\":{\"S\":\"${SERVICE}#975678945875#$([ $SERVICE = iam ] && echo global || echo us-east-1)\"}}" \
    --select COUNT --query 'Count' --output text 2>/dev/null || echo 0)
  echo "${SERVICE}: ${COUNT} items"
done
```

### 4e. End-to-End Browser Check

1. Navigate to `https://status.aws.dcli.com`
2. You should be redirected to the Cognito Hosted UI login page
3. Log in with your DCLI SSO credentials
4. After login, you should be redirected back to `/auth/callback` then to `/dashboard`
5. The dashboard should load EC2, S3, IAM, RDS, Lambda, etc.

---

## Adding a New Member Account

### 1. Deploy the IAM Role in the New Account

```bash
NEW_ACCOUNT_PROFILE=<new_account_profile>
MAIN_ACCOUNT_ID=975678945875
LAMBDA_ROLE=inventory-dashboard-InventoryFunctionRole-QXNabHTvrDtL

aws cloudformation deploy \
  --template-file member-account-role.yaml \
  --stack-name inventory-dashboard-member-role \
  --region us-east-1 \
  --profile ${NEW_ACCOUNT_PROFILE} \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    MainAccountId=${MAIN_ACCOUNT_ID} \
    LambdaExecutionRoleName=${LAMBDA_ROLE} \
    RoleName=InventoryReadRole \
    ExternalId=""
```

### 2. Add the Account to Both Lambda Functions

```bash
NEW_ACCOUNT_ID=<12-digit-account-id>
NEW_ACCOUNT_NAME=<friendly-name>

# Current INVENTORY_ACCOUNTS value:
# 975678945875:dcli-sharedsvcs2,529088296711:dcli_sandbox1,687360398174:dcli_sandbox2
# Append new account:
NEW_ACCOUNTS="975678945875:dcli-sharedsvcs2,529088296711:dcli_sandbox1,687360398174:dcli_sandbox2,${NEW_ACCOUNT_ID}:${NEW_ACCOUNT_NAME}"

for FUNC in \
  inventory-dashboard-InventoryFunction-dIyVdcG9NMS9 \
  inventory-dashboard-RefreshFunction-ZP5pOYnIOIgM; do
  aws lambda update-function-configuration \
    --function-name ${FUNC} \
    --region us-east-1 \
    --profile dcli_sharedsvcs2 \
    --environment "{\"Variables\":{
      \"ALLOWED_REGIONS\":\"us-east-1,us-east-2\",
      \"COGNITO_CLIENT_ID\":\"776457erti67mcbdlffj8idon6\",
      \"COGNITO_DOMAIN\":\"status.aws.dcli.com\",
      \"COGNITO_REGION\":\"us-east-2\",
      \"COGNITO_USER_POOL_ID\":\"us-east-2_Cb4IW3we4\",
      \"INVENTORY_ACCOUNTS\":\"${NEW_ACCOUNTS}\",
      \"INVENTORY_TABLE_NAME\":\"aws-inventory-data-dev\",
      \"METADATA_TABLE_NAME\":\"aws-inventory-metadata-dev\",
      \"REFRESH_FUNCTION_NAME\":\"inventory-dashboard-RefreshFunction-ZP5pOYnIOIgM\"
    }}" \
    --query 'LastModified' --output text
done
```

### 3. Trigger a Refresh

```bash
aws lambda invoke \
  --function-name inventory-dashboard-RefreshFunction-ZP5pOYnIOIgM \
  --region us-east-1 --profile dcli_sharedsvcs2 \
  --payload "{\"accounts\":[\"${NEW_ACCOUNT_ID}\"]}" \
  --cli-binary-format raw-in-base64-out \
  /tmp/new-account-refresh.json && \
cat /tmp/new-account-refresh.json | python3 -c "
import json, sys
r = json.load(sys.stdin)
body = json.loads(r['body'])
print('Total:', body.get('totalResources'))
"
```

---

## Re-deploying After Code Changes

### Backend Only (Python source changed)

```bash
cd backend/
# Quick patch — no SAM needed
rm -rf /tmp/lambda-package && mkdir /tmp/lambda-package
cp -r src/* /tmp/lambda-package/
cd /tmp/lambda-package && zip -r /tmp/lambda-full.zip . -q && cd -

aws lambda update-function-code \
  --function-name inventory-dashboard-InventoryFunction-dIyVdcG9NMS9 \
  --region us-east-1 --profile dcli_sharedsvcs2 \
  --zip-file fileb:///tmp/lambda-full.zip --query 'LastModified' --output text

aws lambda update-function-code \
  --function-name inventory-dashboard-RefreshFunction-ZP5pOYnIOIgM \
  --region us-east-1 --profile dcli_sharedsvcs2 \
  --zip-file fileb:///tmp/lambda-full.zip --query 'LastModified' --output text
```

### Backend — New Dependencies Added (`requirements.txt` changed)

```bash
cd backend/
./setup_layer.sh   # re-installs deps into layer/
sam build && sam deploy --profile dcli_sharedsvcs2
```

### Frontend Only (React/TypeScript changed)

```bash
cd frontend/
npm run build
aws s3 sync out/ s3://dcli-inventory-dashboard-frontend \
  --profile dcli_sharedsvcs2 --region us-east-2 --delete \
  --exclude "*.html" --exclude "*.json" \
  --cache-control "public, max-age=31536000, immutable"
aws s3 sync out/ s3://dcli-inventory-dashboard-frontend \
  --profile dcli_sharedsvcs2 --region us-east-2 \
  --include "*.html" --include "*.json" \
  --cache-control "no-cache, no-store, must-revalidate"
aws cloudfront create-invalidation \
  --distribution-id E3REYNS02TTB3V --paths "/*" \
  --profile dcli_sharedsvcs2 --query 'Invalidation.Id' --output text
```

### Environment Variable Changed (`frontend/.env`)

`NEXT_PUBLIC_*` variables are baked into the JS bundle at build time. Always rebuild and redeploy the frontend when changing them:

```bash
# Edit frontend/.env, then:
cd frontend/ && npm run build
# ... then S3 sync + CloudFront invalidation as above
```

---

## Troubleshooting

### 403 Forbidden on API Requests

The API Gateway uses a Cognito User Pools authorizer. 403 is returned when:

1. **No `Authorization` header** — user is not logged in; clear `localStorage` and log in again.
2. **Expired token** — token is older than 1 hour; the frontend auto-refreshes using the stored `refreshToken`, but if that also expired (default: 30 days), a fresh login is required.
3. **Wrong Cognito region/pool** — verify `NEXT_PUBLIC_COGNITO_*` env vars match the pool (`us-east-2_Cb4IW3we4`).

### "No authorization code received" After Login

Caused by a redirect stripping the `?code=` query parameter. Verify:

- `trailingSlash: false` in `frontend/next.config.js`
- The Cognito App Client callback URL is exactly `https://status.aws.dcli.com/auth/callback` (no trailing slash)
- S3 error document is `index.html` (not a redirect)
- CloudFront custom error responses send `index.html` for 403 and 404 with HTTP 200

### JS Files Return `text/html` (SyntaxError in Console)

CloudFront is returning `index.html` for JS chunk requests. Cause: WAF is blocking the requests and returning an HTML error page, or S3 bucket policy is misconfigured.

```bash
# Check WAF allowed IPs
aws wafv2 list-ip-sets \
  --scope CLOUDFRONT \
  --region us-east-1 \
  --profile dcli_sharedsvcs2 \
  --query 'IPSets[?Name==`inventory-dashboard-dev-allowed-ips`].{Name:Name,Id:Id}'

# Get your current IP
curl -s https://checkip.amazonaws.com
```

Add your IP to the WAF IP set if missing.

### Dashboard Shows 0 Results for IAM

IAM is a global service. Data is stored with `region=global` in DynamoDB (`pk = iam#ACCOUNT_ID#global`). The backend must query `region=global` for IAM, not `us-east-1`. This is handled by `get_regions_from_params()` in `backend/src/app.py` — if results are 0, verify the function returns `['global']` for service `iam`.

### RDS Shows 0 Results

RDS instances in this environment are in `us-east-2`. Verify `ALLOWED_REGIONS` in both Lambda functions includes `us-east-2`, then trigger a refresh:

```bash
aws lambda invoke \
  --function-name inventory-dashboard-RefreshFunction-ZP5pOYnIOIgM \
  --region us-east-1 --profile dcli_sharedsvcs2 \
  --payload '{"service":"rds"}' \
  --cli-binary-format raw-in-base64-out /tmp/rds.json && cat /tmp/rds.json
```

### `sam deploy` Fails with `ROLLBACK_COMPLETE`

Delete the failed stack and redeploy:

```bash
aws cloudformation delete-stack \
  --stack-name inventory-dashboard \
  --region us-east-1 \
  --profile dcli_sharedsvcs2

# Wait for deletion, then redeploy
sam deploy --guided --profile dcli_sharedsvcs2
```

### CloudFront Serves Stale Content After Deploy

Always invalidate after S3 sync. If the invalidation completed but the browser still shows old content, force a hard refresh (`Ctrl+Shift+R` / `Cmd+Shift+R`) or clear the browser cache.
