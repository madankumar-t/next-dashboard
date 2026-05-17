####################################################################
# Lambda execution role – shared by both functions
####################################################################
resource "aws_iam_role" "lambda_execution" {
  name = "${local.name_prefix}-lambda-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

####################################################################
# InventoryFunction policy – read DynamoDB, invoke RefreshFunction,
# list Org accounts, get caller identity
####################################################################
resource "aws_iam_role_policy" "inventory_function" {
  name = "inventory-function-policy"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBRead"
        Effect = "Allow"
        Action = [
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:GetItem",
          "dynamodb:BatchGetItem",
        ]
        Resource = [
          aws_dynamodb_table.inventory.arn,
          aws_dynamodb_table.metadata.arn,
          "${aws_dynamodb_table.metadata.arn}/index/*",
        ]
      },
      {
        Sid      = "InvokeRefreshFunction"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.refresh.arn
      },
      {
        Sid    = "OrgAndSTS"
        Effect = "Allow"
        Action = [
          "organizations:ListAccounts",
          "organizations:DescribeAccount",
          "sts:GetCallerIdentity",
        ]
        Resource = "*"
      },
    ]
  })
}

####################################################################
# RefreshFunction policy – collect from AWS APIs via AssumeRole,
# write collected data to DynamoDB
####################################################################
resource "aws_iam_role_policy" "refresh_function" {
  name = "refresh-function-policy"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBWrite"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:BatchWriteItem",
          "dynamodb:GetItem",
        ]
        Resource = [
          aws_dynamodb_table.inventory.arn,
          aws_dynamodb_table.metadata.arn,
          "${aws_dynamodb_table.metadata.arn}/index/*",
        ]
      },
      {
        # Assume the read role in every member account
        Sid      = "CrossAccountAssumeRole"
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = "arn:aws:iam::*:role/${var.inventory_role_name}"
      },
      {
        # Collect from the server account itself without role assumption
        Sid    = "LocalAWSReadAccess"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "s3:ListAllMyBuckets",
          "s3:GetBucket*",
          "rds:Describe*",
          "dynamodb:ListTables",
          "dynamodb:DescribeTable",
          "iam:ListRoles",
          "iam:GetRole*",
          "eks:List*",
          "eks:Describe*",
          "ecs:List*",
          "ecs:Describe*",
          "lambda:ListFunctions",
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration",
          "lambda:ListTags",
          "organizations:List*",
          "organizations:Describe*",
          "sts:GetCallerIdentity",
        ]
        Resource = "*"
      },
    ]
  })
}
