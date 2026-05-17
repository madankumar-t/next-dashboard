# Frontend Infrastructure as Code

This directory contains CloudFormation templates and scripts to automate the frontend infrastructure deployment.

## What Was Changed

### CloudFront Error Pages Configuration

**Problem:** CloudFront returned 403/404 errors for SPA routes like `/auth/callback` and `/dashboard` because these routes don't exist as physical files in S3.

**Solution:** Added custom error responses to CloudFront:

```yaml
CustomErrorResponses:
  - ErrorCode: 403
    ResponseCode: 200
    ResponsePagePath: /index.html
    ErrorCachingMinTTL: 0
  - ErrorCode: 404
    ResponseCode: 200
    ResponsePagePath: /index.html
    ErrorCachingMinTTL: 0
```

**Why this works:**
- When CloudFront can't find a file (403/404), it returns `/index.html` with HTTP 200
- The React app loads and handles client-side routing
- User sees the correct page without errors

## Files Created

1. **frontend-infrastructure.yaml** - CloudFormation template for S3 + CloudFront
2. **deploy-infrastructure.ps1** - PowerShell script to deploy the infrastructure
3. **INFRASTRUCTURE_GUIDE.md** - This file

## Deployment Options

### Option 1: Use Existing Infrastructure (Current Setup)

If you already have S3 + CloudFront deployed, you don't need to redeploy. The error pages are already configured via CLI.

To verify:
```powershell
aws cloudfront get-distribution --id E1WFQYNOO84626 --query "Distribution.DistributionConfig.CustomErrorResponses"
```

### Option 2: Deploy with CloudFormation (Recommended for Future)

For future deployments or new environments, use the CloudFormation template:

#### Initial Deployment (without custom domain)

```powershell
cd frontend
.\deploy-infrastructure.ps1 -StackName "aws-inventory-frontend" -BucketName "your-bucket-name"
```

#### With Custom Domain

```powershell
.\deploy-infrastructure.ps1 `
    -StackName "aws-inventory-frontend" `
    -BucketName "your-bucket-name" `
    -CustomDomain "aws-dashboard.poc.nexturn.com" `
    -CertificateArn "arn:aws:acm:us-east-1:ACCOUNT_ID:certificate/CERT_ID"
```

#### Update Existing Stack

```powershell
.\deploy-infrastructure.ps1 -StackName "aws-inventory-frontend" -Update
```

## Complete Deployment Workflow

### 1. Deploy Backend (one time)

```powershell
cd backend
./setup_layer.sh     # Or PowerShell equivalent
sam build
sam deploy --guided
```

Note the API Gateway URL from outputs.

### 2. Deploy Frontend Infrastructure (one time)

```powershell
cd frontend
.\deploy-infrastructure.ps1 -StackName "aws-inventory-frontend"
```

Get the CloudFront Distribution ID and bucket name from outputs.

### 3. Configure Frontend Environment

Create `.env` file with values from backend deployment:

```env
NEXT_PUBLIC_COGNITO_USER_POOL_ID=us-east-1_CiQtVfFnM
NEXT_PUBLIC_COGNITO_CLIENT_ID=39v2nj1ueoajpeqfrckpthd0go
NEXT_PUBLIC_COGNITO_REGION=us-east-1
NEXT_PUBLIC_COGNITO_DOMAIN=nxt-inventory-dash-4792
NEXT_PUBLIC_API_URL=https://YOUR-API-ID.execute-api.us-east-1.amazonaws.com/prod
NEXT_EXPORT=true
```

### 4. Build and Deploy Frontend (every code change)

```powershell
cd frontend

# Build static site
npm run build:static

# Upload to S3
aws s3 sync out/ s3://YOUR-BUCKET-NAME --delete

# Invalidate CloudFront cache
aws cloudfront create-invalidation --distribution-id YOUR-DIST-ID --paths "/*"
```

## Key Configuration Details

### CloudFront Cache Policies

- **CachePolicyId: 4135ea2d-6df8-44a3-9df3-4b5a84be39ad** - Managed-CachingOptimized
- **OriginRequestPolicyId: b689b0a8-53d0-40ab-baf2-68738e2966ac** - Managed-CORS-S3Origin

### Error Page Configuration

```json
{
  "ErrorCode": 403,
  "ResponseCode": "200",
  "ResponsePagePath": "/index.html",
  "ErrorCachingMinTTL": 0
}
```

- **ErrorCode**: The error from S3 (403/404)
- **ResponseCode**: What CloudFront returns to the browser (200)
- **ResponsePagePath**: The file CloudFront serves (/index.html)
- **ErrorCachingMinTTL**: How long to cache errors (0 = no caching)

## Troubleshooting

### CloudFront still returns 403/404

Wait 3-5 minutes for CloudFront to deploy changes, then:

```powershell
aws cloudfront create-invalidation --distribution-id YOUR-DIST-ID --paths "/*"
```

### Custom domain returns 502

Check DNS points to CloudFront:

```powershell
# Get CloudFront domain
aws cloudfront get-distribution --id YOUR-DIST-ID --query "Distribution.DomainName" --output text

# Update DNS CNAME record to point to the CloudFront domain
```

### CORS errors when calling API

Ensure API Gateway has CORS enabled and the correct origins configured.

## Infrastructure as Code Benefits

✅ **Repeatable** - Deploy to dev/staging/prod with same template  
✅ **Version Controlled** - Track changes in Git  
✅ **Automated** - No manual console clicking  
✅ **Documented** - Template serves as documentation  
✅ **Rollback Ready** - CloudFormation can rollback on errors

## Manual Changes Made

The following was done manually via CLI (now codified in the template):

1. ✅ Added CloudFront custom error responses for 403/404
2. ✅ Configured error pages to return /index.html with 200 status
3. ✅ Set ErrorCachingMinTTL to 0

These changes are now permanent and will persist through CloudFront updates.
