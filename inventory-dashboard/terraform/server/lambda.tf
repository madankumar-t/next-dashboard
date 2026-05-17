####################################################################
# Build Lambda layer (Python deps)
#
# The null_resource shells out to pip during `terraform apply`.
# Requirements:
#   - Python 3.12 + pip available in the Spacelift worker
#   - zip available in the Spacelift worker
#
# The layer is rebuilt only when requirements.txt changes.
####################################################################
resource "null_resource" "build_lambda_layer" {
  triggers = {
    # always_run forces the build script to execute on every apply.
    # Spacelift runners are ephemeral — the ./build/ directory is gone after
    # each run, so the zip must be rebuilt each time regardless of whether
    # requirements.txt changed. The Lambda layer version is only re-uploaded
    # when source_code_hash (derived from requirements.txt) actually changes.
    always_run        = timestamp()
    requirements_hash = filemd5("${local.backend_root_path}/requirements.txt")
  }

  provisioner "local-exec" {
    command = "${path.root}/scripts/build_layer.sh ${local.backend_root_path} ${local.build_path}"
  }
}

####################################################################
# Zip artifacts
#
# The layer zip is created by build_layer.sh (run via null_resource above).
# archive_file is NOT used for the layer because it runs during plan,
# before the null_resource has built the source directory.
####################################################################
data "archive_file" "inventory_function" {
  type        = "zip"
  source_dir  = local.backend_src_path
  output_path = "${local.build_path}/inventory_function.zip"
}

####################################################################
# Lambda layer version
####################################################################
resource "aws_lambda_layer_version" "python_deps" {
  layer_name  = "${local.name_prefix}-python-deps"
  description = "boto3 and botocore for inventory-dashboard"

  # The zip is written by build_layer.sh during apply (null_resource above).
  # source_code_hash is derived from requirements.txt — a repo file that exists
  # at plan time — so Terraform can detect dependency changes without reading
  # the zip during the plan phase.
  filename         = "${local.build_path}/lambda_layer.zip"
  source_code_hash = filebase64sha256("${local.backend_root_path}/requirements.txt")

  compatible_runtimes = ["python3.12"]
  depends_on          = [null_resource.build_lambda_layer]
}

####################################################################
# InventoryFunction – API request handler
####################################################################
resource "aws_lambda_function" "inventory" {
  function_name    = "${local.name_prefix}-inventory"
  role             = aws_iam_role.lambda_execution.arn
  handler          = "app.lambda_handler"
  runtime          = "python3.12"
  timeout          = 300
  memory_size      = 512
  filename         = data.archive_file.inventory_function.output_path
  source_code_hash = data.archive_file.inventory_function.output_base64sha256
  layers           = [aws_lambda_layer_version.python_deps.arn]

  environment {
    variables = {
      INVENTORY_TABLE_NAME  = aws_dynamodb_table.inventory.name
      METADATA_TABLE_NAME   = aws_dynamodb_table.metadata.name
      REFRESH_FUNCTION_NAME = aws_lambda_function.refresh.function_name
      INVENTORY_ACCOUNTS    = var.inventory_accounts
      INVENTORY_ROLE_NAME   = var.inventory_role_name
      INVENTORY_REGIONS     = var.inventory_regions
      EXTERNAL_ID           = var.external_id
      ROLE_SESSION_NAME     = "InventoryDashboardSession"
      ENVIRONMENT           = var.environment
    }
  }

  depends_on = [aws_cloudwatch_log_group.inventory_function]
}

####################################################################
# RefreshFunction – collects data from member accounts into DynamoDB
####################################################################
resource "aws_lambda_function" "refresh" {
  function_name    = "${local.name_prefix}-refresh"
  role             = aws_iam_role.lambda_execution.arn
  handler          = "refresh_handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 900
  memory_size      = 1024
  filename         = data.archive_file.inventory_function.output_path
  source_code_hash = data.archive_file.inventory_function.output_base64sha256
  layers           = [aws_lambda_layer_version.python_deps.arn]

  environment {
    variables = {
      INVENTORY_TABLE_NAME = aws_dynamodb_table.inventory.name
      METADATA_TABLE_NAME  = aws_dynamodb_table.metadata.name
      INVENTORY_ROLE_NAME  = var.inventory_role_name
      INVENTORY_REGIONS    = var.inventory_regions
      EXTERNAL_ID          = var.external_id
      ROLE_SESSION_NAME    = "InventoryDashboardSession"
      ENVIRONMENT          = var.environment
      INVENTORY_ACCOUNTS   = var.inventory_accounts
    }
  }

  depends_on = [aws_cloudwatch_log_group.refresh_function]
}

####################################################################
# Lambda permission – allow API Gateway to invoke InventoryFunction
####################################################################
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.inventory.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

####################################################################
# Lambda permission – allow EventBridge to invoke RefreshFunction
####################################################################
resource "aws_lambda_permission" "eventbridge_invoke" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.refresh.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.refresh_schedule.arn
}
