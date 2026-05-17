#!/bin/bash
# CloudFront Distribution Deployment
# Run after S3 deployment is complete

set -e

BUCKET_NAME="aws-inventory-dashboard-frontend"
REGION="us-east-2"

echo "📡 Creating CloudFront Distribution..."
echo "======================================"
echo ""

# Create CloudFront distribution
DIST_ID=$(aws cloudfront create-distribution \
    --origin-domain-name $BUCKET_NAME.s3.us-east-2.amazonaws.com \
    --default-root-object index.html \
    --enabled \
    --default-cache-behavior '{
        "TargetOriginId": "S3Origin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
        "AllowedMethods": ["GET", "HEAD"]
    }' \
    --cache-behaviors '[
        {
            "PathPattern": "*.html",
            "TargetOriginId": "S3Origin",
            "ViewerProtocolPolicy": "redirect-to-https",
            "CachePolicyId": "4135ea3d-c35d-46eb-81d7-reeSJHOUqe21",
            "AllowedMethods": ["GET", "HEAD"]
        }
    ]' \
    --origins "Items=[{DomainName=$BUCKET_NAME.s3.us-east-2.amazonaws.com,Id=S3Origin,S3OriginConfig={OriginAccessIdentity=''}}],Quantity=1" \
    --custom-error-responses "Items=[
        {ErrorCode=403,ResponseCode=200,ResponsePagePath=/index.html},
        {ErrorCode=404,ResponseCode=200,ResponsePagePath=/index.html}
    ],Quantity=2" \
    --query 'Distribution.Id' \
    --output text)

echo "✓ Distribution created: $DIST_ID"
echo ""
echo "📋 Getting CloudFront domain name..."
echo ""

# Wait a moment for distribution to be ready
sleep 5

CLOUDFRONT_DOMAIN=$(aws cloudfront get-distribution \
    --id $DIST_ID \
    --query 'Distribution.DomainName' \
    --output text)

echo "✅ CloudFront URL: https://$CLOUDFRONT_DOMAIN"
echo ""
echo "⏳ Distribution is being deployed (this takes 10-15 minutes)..."
echo ""
echo "Next Steps:"
echo "1. Wait for distribution to be DEPLOYED (check AWS Console)"
echo "2. Update Cognito callback URLs:"
echo ""
echo "   Callback URLs:"
echo "   - https://$CLOUDFRONT_DOMAIN"
echo "   - https://$CLOUDFRONT_DOMAIN/auth/callback"
echo ""
echo "   Sign-out URLs:"
echo "   - https://$CLOUDFRONT_DOMAIN"
echo ""
echo "3. Save this Distribution ID: $DIST_ID"
echo ""
