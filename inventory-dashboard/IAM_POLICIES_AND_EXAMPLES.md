# IAM Policies and Trust Policy Examples

This document provides IAM policy examples for the AWS Inventory Dashboard multi-account setup.

---

## 1. Member Account Role - Trust Policy

The trust policy allows the main account's Lambda execution role to assume this role.

### Example Trust Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::123456789012:role/aws-inventory-dashboard-RefreshFunctionRole-XXXXXXXX"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "your-secure-external-id-here"
        }
      }
    }
  ]
}
```

### Using Account Root (Less Secure - Not Recommended)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::123456789012:root"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "your-secure-external-id-here"
        }
      }
    }
  ]
}
```

**⚠️ Security Note:** Using account root is less secure. Prefer specific role ARN.

---

## 2. Member Account Role - Permission Policy

This policy grants read-only access to all AWS services needed for inventory collection.

### Complete Permission Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EC2ReadAccess",
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "ec2:GetConsoleOutput",
        "ec2:GetConsoleScreenshot"
      ],
      "Resource": "*"
    },
    {
      "Sid": "S3ReadAccess",
      "Effect": "Allow",
      "Action": [
        "s3:ListAllMyBuckets",
        "s3:GetBucketLocation",
        "s3:GetBucketVersioning",
        "s3:GetBucketAcl",
        "s3:GetBucketPolicy",
        "s3:GetBucketEncryption",
        "s3:GetBucketPublicAccessBlock",
        "s3:GetBucketTagging",
        "s3:ListBucket"
      ],
      "Resource": "*"
    },
    {
      "Sid": "RDSReadAccess",
      "Effect": "Allow",
      "Action": [
        "rds:Describe*",
        "rds:ListTagsForResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DynamoDBReadAccess",
      "Effect": "Allow",
      "Action": [
        "dynamodb:ListTables",
        "dynamodb:DescribeTable",
        "dynamodb:ListTagsOfResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMReadAccess",
      "Effect": "Allow",
      "Action": [
        "iam:ListRoles",
        "iam:GetRole",
        "iam:GetRolePolicy",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies",
        "iam:ListRoleTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "VPCReadAccess",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets",
        "ec2:DescribeInternetGateways",
        "ec2:DescribeNatGateways",
        "ec2:DescribeRouteTables",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeNetworkAcls",
        "ec2:DescribeVpcPeeringConnections"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EKSReadAccess",
      "Effect": "Allow",
      "Action": [
        "eks:ListClusters",
        "eks:DescribeCluster",
        "eks:ListNodegroups",
        "eks:DescribeNodegroup",
        "eks:ListTagsForResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ECSReadAccess",
      "Effect": "Allow",
      "Action": [
        "ecs:ListClusters",
        "ecs:DescribeClusters",
        "ecs:ListServices",
        "ecs:DescribeServices",
        "ecs:ListTasks",
        "ecs:DescribeTasks",
        "ecs:ListTaskDefinitions",
        "ecs:DescribeTaskDefinitions"
      ],
      "Resource": "*"
    },
    {
      "Sid": "LambdaReadAccess",
      "Effect": "Allow",
      "Action": [
        "lambda:ListFunctions",
        "lambda:GetFunction",
        "lambda:GetFunctionConfiguration",
        "lambda:ListTags",
        "lambda:ListVersionsByFunction",
        "lambda:ListAliases"
      ],
      "Resource": "*"
    },
    {
      "Sid": "STSReadAccess",
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## 3. Main Account - RefreshFunction Execution Role

This role is automatically created by SAM template. It needs permissions to:

1. Assume roles in member accounts
2. Read resources from AWS services
3. Write to DynamoDB

### Key Permissions (Managed by SAM Template)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "s3:ListAllMyBuckets",
        "s3:GetBucket*",
        "rds:Describe*",
        "dynamodb:ListTables",
        "dynamodb:DescribeTable",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query",
        "dynamodb:Scan",
        "dynamodb:BatchWriteItem",
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
        "sts:AssumeRole",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query",
        "dynamodb:Scan",
        "dynamodb:BatchWriteItem"
      ],
      "Resource": [
        "arn:aws:dynamodb:*:*:table/aws-inventory-data-*",
        "arn:aws:dynamodb:*:*:table/aws-inventory-metadata-*"
      ]
    }
  ]
}
```

---

## 4. Main Account - InventoryFunction Execution Role

This role is automatically created by SAM template. It needs permissions to:

1. Read from DynamoDB
2. Invoke RefreshFunction (optional, for on-demand refresh)

### Key Permissions (Managed by SAM Template)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:Query",
        "dynamodb:Scan",
        "dynamodb:GetItem",
        "dynamodb:BatchGetItem"
      ],
      "Resource": [
        "arn:aws:dynamodb:*:*:table/aws-inventory-data-*",
        "arn:aws:dynamodb:*:*:table/aws-inventory-metadata-*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "lambda:InvokeFunction"
      ],
      "Resource": "arn:aws:lambda:*:*:function:aws-inventory-dashboard-RefreshFunction-*"
    }
  ]
}
```

---

## 5. Setting Up Member Account Role

### Using CloudFormation (Recommended)

```bash
aws cloudformation create-stack \
  --stack-name inventory-read-role \
  --template-body file://member-account-role.yaml \
  --parameters \
    ParameterKey=MainAccountId,ParameterValue=123456789012 \
    ParameterKey=LambdaExecutionRoleName,ParameterValue=aws-inventory-dashboard-RefreshFunctionRole-XXXXXXXX \
    ParameterKey=ExternalId,ParameterValue=your-secure-external-id \
    ParameterKey=RoleName,ParameterValue=InventoryReadRole \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1
```

### Using AWS CLI (Manual)

```bash
# 1. Create trust policy file
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::123456789012:role/aws-inventory-dashboard-RefreshFunctionRole-XXXXXXXX"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "your-secure-external-id"
        }
      }
    }
  ]
}
EOF

# 2. Create role
aws iam create-role \
  --role-name InventoryReadRole \
  --assume-role-policy-document file://trust-policy.json

# 3. Attach permission policy (use the policy from section 2 above)
aws iam put-role-policy \
  --role-name InventoryReadRole \
  --policy-name InventoryReadPolicy \
  --policy-document file://permission-policy.json
```

---

## 6. Finding Lambda Execution Role ARN

After deploying the SAM template, find the Lambda execution role ARN:

```bash
# Method 1: Using AWS CLI
aws iam list-roles \
  --query 'Roles[?contains(RoleName, `InventoryFunction`) || contains(RoleName, `RefreshFunction`)].Arn' \
  --output text

# Method 2: From CloudFormation stack outputs
aws cloudformation describe-stacks \
  --stack-name inventory-dashboard-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`InventoryFunctionRoleInfo`].OutputValue' \
  --output text

# Method 3: From Lambda function configuration
aws lambda get-function \
  --function-name aws-inventory-dashboard-RefreshFunction-XXXXXXXX \
  --query 'Configuration.Role' \
  --output text
```

---

## 7. Security Best Practices

### ✅ Recommended

1. **Use External ID:** Always set External ID in trust policy
2. **Specific Role ARN:** Use specific Lambda execution role ARN, not account root
3. **Least Privilege:** Only grant read permissions needed for inventory
4. **Regular Audits:** Review IAM policies regularly
5. **CloudTrail:** Enable CloudTrail to monitor AssumeRole calls

### ❌ Avoid

1. **Account Root in Trust Policy:** Less secure, harder to audit
2. **Wildcard Resources:** If possible, restrict to specific resources
3. **Write Permissions:** Member account role should NOT have write permissions
4. **Hardcoded Credentials:** Never hardcode credentials in code

---

## 8. Troubleshooting

### Issue: "Access Denied" when assuming role

**Possible Causes:**
1. Trust policy doesn't match Lambda execution role ARN
2. External ID mismatch
3. Role doesn't exist in member account

**Solution:**
```bash
# Verify trust policy
aws iam get-role --role-name InventoryReadRole --query 'Role.AssumeRolePolicyDocument'

# Verify External ID matches
# Check Lambda environment variable EXTERNAL_ID matches trust policy condition
```

### Issue: "Cannot list resources" after assuming role

**Possible Causes:**
1. Permission policy missing required actions
2. Resource-level restrictions (if any)

**Solution:**
```bash
# Verify permission policy
aws iam get-role-policy \
  --role-name InventoryReadRole \
  --policy-name InventoryReadPolicy

# Test with AWS CLI
aws sts assume-role \
  --role-arn arn:aws:iam::MEMBER_ACCOUNT:role/InventoryReadRole \
  --role-session-name test-session \
  --external-id your-external-id

# Use returned credentials to test access
```

---

## 9. Example: Complete Setup Script

```bash
#!/bin/bash

# Configuration
MAIN_ACCOUNT_ID="123456789012"
MEMBER_ACCOUNT_ID="987654321098"
EXTERNAL_ID="secure-external-id-$(date +%s)"
ROLE_NAME="InventoryReadRole"

# Get Lambda execution role ARN from main account
LAMBDA_ROLE_ARN=$(aws iam list-roles \
  --query "Roles[?contains(RoleName, 'RefreshFunction')].Arn" \
  --output text \
  --region us-east-1)

echo "Lambda Role ARN: $LAMBDA_ROLE_ARN"

# Create trust policy
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "$LAMBDA_ROLE_ARN"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "$EXTERNAL_ID"
        }
      }
    }
  ]
}
EOF

# Create role in member account (requires member account credentials)
aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document file://trust-policy.json \
  --profile member-account

# Attach permission policy (use member-account-role.yaml template)
aws cloudformation create-stack \
  --stack-name inventory-read-role \
  --template-body file://member-account-role.yaml \
  --parameters \
    ParameterKey=MainAccountId,ParameterValue=$MAIN_ACCOUNT_ID \
    ParameterKey=LambdaExecutionRoleName,ParameterValue=$(basename $LAMBDA_ROLE_ARN) \
    ParameterKey=ExternalId,ParameterValue=$EXTERNAL_ID \
    ParameterKey=RoleName,ParameterValue=$ROLE_NAME \
  --capabilities CAPABILITY_NAMED_IAM \
  --profile member-account

echo "Setup complete! External ID: $EXTERNAL_ID"
echo "Update main account Lambda environment variable EXTERNAL_ID with: $EXTERNAL_ID"
```

---

## 10. References

- [AWS IAM AssumeRole Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use.html)
- [External ID Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-user_externalid.html)
- [Cross-Account Access Patterns](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_common-scenarios_aws-accounts.html)

---

**Last Updated:** 2024-12-19

