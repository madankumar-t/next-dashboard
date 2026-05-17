#!/bin/bash
# Frontend S3 + CloudFront Deployment Script
# Run this from your local machine with proper AWS credentials

set -e

BUCKET_NAME="aws-inventory-dashboard-frontend"
REGION="us-east-2"
DISTRIBUTION_ID=""  # You'll get this after creating CloudFront distribution

echo "📦 Frontend Deployment to S3 + CloudFront"
echo "==========================================="
echo ""

# Step 1: Create S3 Bucket
echo "Step 1: Creating S3 bucket..."
aws s3 mb s3://$BUCKET_NAME --region $REGION 2>/dev/null || echo "✓ Bucket already exists"

# Step 2: Enable Static Website Hosting
echo "Step 2: Enabling static website hosting..."
aws s3 website s3://$BUCKET_NAME \
    --index-document index.html \
    --error-document index.html

# Step 3: Set Bucket Policy for Public Read
echo "Step 3: Setting bucket policy..."
cat > /tmp/bucket-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
    }
  ]
}
EOF

aws s3api put-bucket-policy \
    --bucket $BUCKET_NAME \
    --policy file:///tmp/bucket-policy.json

# Step 4: Block Public Access Settings (needed for public policy)
echo "Step 4: Configuring public access..."
aws s3api put-public-access-block \
    --bucket $BUCKET_NAME \
    --public-access-block-configuration \
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

# Step 5: Upload Static Files
echo "Step 5: Uploading files to S3..."

# Upload static assets with long cache
aws s3 sync ./frontend/out/ s3://$BUCKET_NAME \
    --delete \
    --cache-control "public, max-age=31536000, immutable" \
    --exclude "*.html" \
    --exclude "*.json" \
    --region $REGION

# Upload HTML/JSON with no cache
aws s3 sync ./frontend/out/ s3://$BUCKET_NAME \
    --cache-control "public, max-age=0, must-revalidate" \
    --include "*.html" \
    --include "*.json" \
    --region $REGION

echo ""
echo "✅ S3 Deployment Complete!"
echo ""
echo "Next Steps:"
echo "1. Create CloudFront Distribution (see CLOUDFRONT_SETUP.md)"
echo "2. Update Cognito callback URLs with the CloudFront domain"
echo ""
echo "S3 Website URL: http://$BUCKET_NAME.s3-website.$REGION.amazonaws.com"
