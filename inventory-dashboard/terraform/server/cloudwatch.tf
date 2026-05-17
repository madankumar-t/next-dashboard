####################################################################
# CloudWatch log groups for Lambda functions
####################################################################
resource "aws_cloudwatch_log_group" "inventory_function" {
  name              = "/aws/lambda/${local.name_prefix}-inventory"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "refresh_function" {
  name              = "/aws/lambda/${local.name_prefix}-refresh"
  retention_in_days = var.log_retention_days
}
