# Frontend Deployment Guide (S3 + CloudFront)

**Status**: ✅ Ready to Deploy

## Environment Configuration

Your frontend has been configured with the following Cognito details:

```env
NEXT_PUBLIC_API_URL=https://coyoct9klh.execute-api.us-east-2.amazonaws.com/prod
NEXT_PUBLIC_COGNITO_USER_POOL_ID=us-east-2_9YNsYJ5zG
NEXT_PUBLIC_COGNITO_CLIENT_ID=2qsoje021lqo2ptrgn8fut2d1p
NEXT_PUBLIC_COGNITO_REGION=us-east-2
NEXT_PUBLIC_COGNITO_DOMAIN=us-east-29ynsyj5zg
```

Location: `frontend/.env.local`

## Build Status

✅ Frontend has been built successfully
- Build output location: `frontend/out/`
- Static files ready for S3 deployment

## Deployment Steps

### Step 1: Deploy to S3 (from your local machine)

The build has completed. Now deploy to S3 from a machine with AWS credentials that have S3 permissions:

```bash
# From the project root directory
./scripts/deploy-frontend-s3.sh
```

Or manually:

```bash
cd /path/to/inventory-dashboard
aws s3 mb s3://aws-inventory-dashboard-frontend --region us-east-2

# Set bucket policy
cat > bucket-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::aws-inventory-dashboard-frontend/*"
    }
  ]
}
EOF

aws s3api put-bucket-policy \
    --bucket aws-inventory-dashboard-frontend \
    --policy file://bucket-policy.json

# Block public access settings
aws s3api put-public-access-block \
    --bucket aws-inventory-dashboard-frontend \
    --public-access-block-configuration \
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

# Enable static website hosting
aws s3 website s3://aws-inventory-dashboard-frontend \
    --index-document index.html \
    --error-document index.html

# Upload files (static assets with long cache)
aws s3 sync frontend/out/ s3://aws-inventory-dashboard-frontend \
    --delete \
    --cache-control "public, max-age=31536000, immutable" \
    --exclude "*.html" \
    --exclude "*.json" \
    --region us-east-2

# Upload HTML/JSON (no cache)
aws s3 sync frontend/out/ s3://aws-inventory-dashboard-frontend \
    --cache-control "public, max-age=0, must-revalidate" \
    --include "*.html" \
    --include "*.json" \
    --region us-east-2
```

### Step 2: Create CloudFront Distribution

Use the AWS Console or run:

```bash
./scripts/deploy-cloudfront.sh
```

**Via AWS Console:**
1. Go to **CloudFront** → **Distributions** → **Create Distribution**
2. **Origin Configuration:**
   - Origin Domain: Select your S3 bucket
   - Keep defaults for other settings
3. **Default Cache Behavior:**
   - Viewer Protocol Policy: **Redirect HTTP to HTTPS**
   - Cache Policy: **Managed-CachingOptimized**
4. **Settings:**
   - Default Root Object: `index.html`
5. **Error Pages:**
   - Add two error responses:
     - **Error Code 403** → Response: `/index.html`, Code: `200`
     - **Error Code 404** → Response: `/index.html`, Code: `200`
6. Create Distribution (takes ~10-15 minutes)

**Get CloudFront Domain:**
```bash
aws cloudformation describe-stacks \
    --stack-name inventory-dashboard-cloudfront \
    --query 'Stacks[0].Outputs[?OutputKey==`DistributionDomainName`].OutputValue' \
    --output text
```

Or from the CloudFront console: Copy the **Distribution Domain Name** (format: `d123abc.cloudfront.net`)

### Step 3: Update Cognito Callback URLs

Once CloudFront is deployed, update your Cognito app client:

1. Go to **AWS Cognito** → **User Pools** → `DCLI-SAML-AUTHENTICATION`
2. Navigate to **App integration** → **App clients and analytics**
3. Select your app client: `DCLI-SAML-AUTHENTICATION`
4. Click **Edit the hosted UI**
5. **Allowed callback URLs** (add these):
   ```
   https://d123abc.cloudfront.net/auth/callback
   https://d123abc.cloudfront.net
   ```
6. **Allowed sign-out URLs** (add this):
   ```
   https://d123abc.cloudfront.net
   ```
7. Save changes

Replace `d123abc.cloudfront.net` with your actual CloudFront domain.

### Step 4: Test Deployment

1. Visit your CloudFront URL: `https://d123abc.cloudfront.net`
2. You should see the login page
3. Click **Login** and verify Cognito authentication works
4. Check browser console for errors (F12)
5. Navigate through the dashboard

## Troubleshooting

### Build Issues
```bash
cd frontend
npm install
npm run build:static
```

### S3 Upload Issues
```bash
# Check bucket exists
aws s3 ls s3://aws-inventory-dashboard-frontend --region us-east-2

# Check bucket policy
aws s3api get-bucket-policy --bucket aws-inventory-dashboard-frontend

# List uploaded files
aws s3 ls s3://aws-inventory-dashboard-frontend --recursive --region us-east-2
```

### CloudFront Issues
- Wait for distribution status to be "Deployed"
- Clear CloudFront cache if content doesn't update:
```bash
aws cloudfront create-invalidation \
    --distribution-id YOUR_DIST_ID \
    --paths "/*"
```

### 403/404 Errors on Route Navigation
Ensure CloudFront error pages are configured correctly (Step 2)

### CORS Errors
Verify backend CORS configuration allows your CloudFront domain

### Login Flow Issues
1. Check Cognito callback URLs match exactly
2. Verify environment variables in `frontend/.env.local`
3. Check browser console for specific error messages

## Files Modified/Created

- ✅ `frontend/.env.local` - Environment variables configured
- ✅ `frontend/out/` - Static build output ready
- ✅ `scripts/deploy-frontend-s3.sh` - S3 deployment script
- ✅ `scripts/deploy-cloudfront.sh` - CloudFront deployment script

## Summary

| Component | Status | Value |
|-----------|--------|-------|
| Frontend Build | ✅ Complete | `frontend/out/` |
| Environment Vars | ✅ Configured | `.env.local` |
| S3 Bucket | ⏳ Ready | `aws-inventory-dashboard-frontend` |
| CloudFront | ⏳ Pending | Run `deploy-cloudfront.sh` |
| Cognito URLs | ⏳ Pending | Update after CloudFront deploy |

## Next Actions

1. Run `./scripts/deploy-frontend-s3.sh` from your local machine
2. Run `./scripts/deploy-cloudfront.sh` or create distribution via console
3. Update Cognito callback URLs (Step 3 above)
4. Test the deployment
5. Share CloudFront URL: `https://d123abc.cloudfront.net`
