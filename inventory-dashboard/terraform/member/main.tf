locals {
  use_external_id = var.external_id != ""
}

####################################################################
# Cross-account IAM role
#
# The server account's Lambda execution role assumes this role to
# collect inventory data from this member account.
####################################################################
resource "aws_iam_role" "inventory_read" {
  name        = var.role_name
  description = "Allows the Inventory Dashboard in account ${var.server_account_id} to read AWS resources in this account"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      merge(
        {
          Effect    = "Allow"
          Principal = { AWS = var.server_lambda_role_arn }
          Action    = "sts:AssumeRole"
        },
        local.use_external_id ? {
          Condition = {
            StringEquals = { "sts:ExternalId" = var.external_id }
          }
        } : {}
      )
    ]
  })

  tags = merge({ ManagedBy = "terraform" }, var.additional_tags)
}

####################################################################
# Read-only inventory policy
####################################################################
resource "aws_iam_role_policy" "inventory_read" {
  name = "InventoryReadPolicy"
  role = aws_iam_role.inventory_read.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2ReadAccess"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ec2:GetConsoleOutput",
          "ec2:GetConsoleScreenshot",
        ]
        Resource = "*"
      },
      {
        Sid    = "S3ReadAccess"
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets",
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning",
          "s3:GetBucketAcl",
          "s3:GetBucketPolicy",
          "s3:GetBucketEncryption",
          "s3:GetBucketPublicAccessBlock",
          "s3:GetBucketTagging",
          "s3:ListBucket",
        ]
        Resource = "*"
      },
      {
        Sid    = "RDSReadAccess"
        Effect = "Allow"
        Action = [
          "rds:Describe*",
          "rds:ListTagsForResource",
        ]
        Resource = "*"
      },
      {
        Sid    = "DynamoDBReadAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:ListTables",
          "dynamodb:DescribeTable",
          "dynamodb:ListTagsOfResource",
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMReadAccess"
        Effect = "Allow"
        Action = [
          "iam:ListRoles",
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListRoleTags",
        ]
        Resource = "*"
      },
      {
        Sid    = "VPCReadAccess"
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeNatGateways",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeNetworkAcls",
          "ec2:DescribeVpcPeeringConnections",
        ]
        Resource = "*"
      },
      {
        Sid    = "EKSReadAccess"
        Effect = "Allow"
        Action = [
          "eks:ListClusters",
          "eks:DescribeCluster",
          "eks:ListNodegroups",
          "eks:DescribeNodegroup",
          "eks:ListTagsForResource",
        ]
        Resource = "*"
      },
      {
        Sid    = "ECSReadAccess"
        Effect = "Allow"
        Action = [
          "ecs:ListClusters",
          "ecs:DescribeClusters",
          "ecs:ListServices",
          "ecs:DescribeServices",
          "ecs:ListTasks",
          "ecs:DescribeTasks",
          "ecs:ListTaskDefinitions",
          "ecs:DescribeTaskDefinitions",
        ]
        Resource = "*"
      },
      {
        Sid    = "LambdaReadAccess"
        Effect = "Allow"
        Action = [
          "lambda:ListFunctions",
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration",
          "lambda:ListTags",
          "lambda:ListVersionsByFunction",
          "lambda:ListAliases",
        ]
        Resource = "*"
      },
      {
        Sid      = "STSReadAccess"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      },
    ]
  })
}
