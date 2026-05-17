####################################################################
# API
####################################################################
output "api_url" {
  description = "Base URL for the Inventory API (set this in the frontend NEXT_PUBLIC_API_URL)"
  value       = "https://${aws_api_gateway_rest_api.main.id}.execute-api.${var.aws_region}.amazonaws.com/${var.environment}"
}

####################################################################
# Frontend
####################################################################
output "frontend_bucket_name" {
  description = "S3 bucket to sync the Next.js static export into"
  value       = aws_s3_bucket.frontend.bucket
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID – needed to invalidate cache after frontend deploy"
  value       = aws_cloudfront_distribution.frontend.id
}

output "cloudfront_domain_name" {
  description = "CloudFront domain name for the dashboard"
  value       = local.has_custom_domain ? "https://${var.custom_domain_name}" : "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

####################################################################
# Cognito
####################################################################
output "cognito_user_pool_id" {
  description = "Cognito User Pool ID – configure in the Next.js frontend"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  description = "Cognito App Client ID – configure in the Next.js frontend"
  value       = aws_cognito_user_pool_client.frontend.id
}

output "cognito_user_pool_domain" {
  description = "Cognito hosted UI domain"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.aws_region}.amazoncognito.com"
}

####################################################################
# DynamoDB
####################################################################
output "inventory_table_name" {
  description = "DynamoDB inventory data table name"
  value       = aws_dynamodb_table.inventory.name
}

output "metadata_table_name" {
  description = "DynamoDB metadata table name"
  value       = aws_dynamodb_table.metadata.name
}

####################################################################
# Lambda execution role (needed by member-account TF)
####################################################################
output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role – provide this to the member-account Terraform as server_lambda_role_arn"
  value       = aws_iam_role.lambda_execution.arn
}

output "server_account_id" {
  description = "AWS account ID where the server stack is deployed"
  value       = var.server_account_id
}

####################################################################
# WAF
####################################################################
output "waf_web_acl_arn" {
  description = "WAF Web ACL ARN attached to the CloudFront distribution"
  value       = aws_wafv2_web_acl.cloudfront.arn
}

####################################################################
# Frontend deploy helper
####################################################################
output "frontend_deploy_commands" {
  description = "Commands to build and deploy the Next.js frontend after Terraform apply"
  value       = <<-EOT
    # Build
    cd frontend && npm run build:static

    # Upload to S3
    aws s3 sync out/ s3://${aws_s3_bucket.frontend.bucket} --delete

    # Invalidate CloudFront cache
    aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.frontend.id} --paths "/*"
  EOT
}
