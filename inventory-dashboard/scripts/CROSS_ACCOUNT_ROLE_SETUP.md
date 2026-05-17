# Cross-Account Role Setup Scripts

Complete scripts and tools to create IAM roles in member accounts for AWS Inventory Dashboard.

## Quick Start

### Option 1: Complete Setup (Recommended)

**Bash:**
```bash
chmod +x scripts/create-cross-account-role-complete.sh
./scripts/create-cross-account-role-complete.sh \
  MEMBER_ACCOUNT_ID \
  MAIN_ACCOUNT_ID \
  LAMBDA_ROLE_NAME \
  EXTERNAL_ID \
  ROLE_NAME
```

**PowerShell:**
```powershell
.\scripts\create-cross-account-role-complete.ps1 \
  -MemberAccountId MEMBER_ACCOUNT_ID \
  -MainAccountId MAIN_ACCOUNT_ID \
  -LambdaRoleName LAMBDA_ROLE_NAME \
  -ExternalId EXTERNAL_ID \
  -RoleName ROLE_NAME
```

### Option 2: CloudFormation (Recommended for Multiple Accounts)

```bash
aws cloudformation create-stack \
  --stack-name inventory-read-role \
  --template-body file://member-account-role.yaml \
  --parameters \
    ParameterKey=MainAccountId,ParameterValue=123456789012 \
    ParameterKey=LambdaExecutionRoleName,ParameterValue=aws-inventory-dashboard-InventoryFunctionRole-XXXXXXXX \
    ParameterKey=ExternalId,ParameterValue=your-external-id \
  --capabilities CAPABILITY_NAMED_IAM
```

## Scripts Overview

### 1. Complete Setup Scripts

#### `create-cross-account-role-complete.sh` / `.ps1`
**Purpose:** Creates role, trust policy, and permissions in one command

**Usage:**
```bash
./create-cross-account-role-complete.sh \
  <MEMBER_ACCOUNT_ID> \
  <MAIN_ACCOUNT_ID> \
  [LAMBDA_ROLE_NAME] \
  [EXTERNAL_ID] \
  [ROLE_NAME]
```

**What it does:**
1. Creates trust policy (allows main account Lambda to assume role)
2. Creates IAM role with trust policy
3. Attaches read-only permissions policy
4. Outputs role ARN

### 2. Trust Policy Generation

#### `create-trust-policy.sh` / `.ps1`
**Purpose:** Generate trust policy JSON only

**Usage:**
```bash
./create-trust-policy.sh MAIN_ACCOUNT_ID LAMBDA_ROLE_NAME EXTERNAL_ID > trust-policy.json
```

**Output:** JSON trust policy file

### 3. Bulk Creation

#### `create-bulk-roles.sh`
**Purpose:** Create roles in multiple accounts from a file

**Usage:**
```bash
# Create accounts file
cat > accounts.txt << EOF
123456789012:Production
987654321098:Development
EOF

# Run bulk creation
./create-bulk-roles.sh MAIN_ACCOUNT_ID accounts.txt LAMBDA_ROLE_NAME EXTERNAL_ID
```

**Accounts File Format:**
```
ACCOUNT_ID:ACCOUNT_NAME
# or
ACCOUNT_ID
```

## Policy Files

### `policies/inventory-read-policy.json`
Complete read-only permissions policy for inventory collection.

**Permissions:**
- EC2: Describe* operations
- S3: List and Get operations
- RDS: Describe* operations
- DynamoDB: List and Describe operations
- IAM: List and Get operations
- VPC: Describe* operations
- EKS: List and Describe operations
- ECS: List and Describe operations
- STS: GetCallerIdentity

## Step-by-Step Manual Creation

### Step 1: Create Trust Policy

**Using Script:**
```bash
./scripts/create-trust-policy.sh \
  123456789012 \
  aws-inventory-dashboard-InventoryFunctionRole-XXXXXXXX \
  your-external-id \
  > trust-policy.json
```

**Manual JSON:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::MAIN_ACCOUNT_ID:role/LAMBDA_ROLE_NAME"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "YOUR_EXTERNAL_ID"
        }
      }
    }
  ]
}
```

### Step 2: Create Role

**AWS CLI:**
```bash
aws iam create-role \
  --role-name InventoryReadRole \
  --assume-role-policy-document file://trust-policy.json \
  --description "Allows AWS Inventory Dashboard to read resources"
```

**AWS Console:**
1. IAM → Roles → Create role
2. Select "AWS account" → "Another AWS account"
3. Enter main account ID
4. Check "Require external ID" (if using)
5. Paste trust policy JSON
6. Name: `InventoryReadRole`

### Step 3: Attach Permissions

**AWS CLI:**
```bash
aws iam put-role-policy \
  --role-name InventoryReadRole \
  --policy-name InventoryReadPolicy \
  --policy-document file://scripts/policies/inventory-read-policy.json
```

**AWS Console:**
1. IAM → Roles → InventoryReadRole
2. Permissions tab → Add permissions → Create inline policy
3. JSON tab → Paste policy from `inventory-read-policy.json`
4. Name: `InventoryReadPolicy`

## Getting Required Values

### Main Account ID
```bash
aws sts get-caller-identity --query Account --output text
```

### Lambda Execution Role Name
```bash
# From CloudFormation
aws cloudformation describe-stack-resources \
  --stack-name aws-inventory-dashboard \
  --query 'StackResources[?ResourceType==`AWS::IAM::Role`].PhysicalResourceId' \
  --output text

# Or list roles
aws iam list-roles \
  --query 'Roles[?contains(RoleName, `InventoryFunction`)].RoleName' \
  --output text
```

### External ID (Optional)
- Set in SAM template parameter `ExternalId`
- Or use any secure random string
- Must match in both main account and member account trust policies

## Verification

### Test Role Assumption

**From Main Account:**
```bash
aws sts assume-role \
  --role-arn arn:aws:iam::MEMBER_ACCOUNT_ID:role/InventoryReadRole \
  --role-session-name test-session \
  --external-id YOUR_EXTERNAL_ID
```

**Expected Output:**
```json
{
  "Credentials": {
    "AccessKeyId": "...",
    "SecretAccessKey": "...",
    "SessionToken": "...",
    "Expiration": "..."
  }
}
```

### Verify Role Exists
```bash
aws iam get-role --role-name InventoryReadRole
```

### Verify Permissions
```bash
aws iam get-role-policy \
  --role-name InventoryReadRole \
  --policy-name InventoryReadPolicy
```

## Troubleshooting

### Error: "Access Denied"
- Verify you have IAM permissions in member account
- Check trust policy allows correct principal
- Verify external ID matches (if using)

### Error: "Role already exists"
- Script will update trust policy automatically
- Or delete and recreate: `aws iam delete-role --role-name InventoryReadRole`

### Error: "Invalid principal"
- Verify Lambda role ARN is correct
- Check account ID is correct
- Ensure role exists in main account

## Security Best Practices

1. **Use External ID** - Always use external ID for cross-account roles
2. **Specific Role ARN** - Use specific Lambda role ARN, not account root
3. **Least Privilege** - Permissions are read-only only
4. **Regular Audits** - Review role usage in CloudTrail
5. **Rotate External ID** - Change external ID periodically

## Examples

### Example 1: Single Account with External ID
```bash
./scripts/create-cross-account-role-complete.sh \
  987654321098 \
  123456789012 \
  aws-inventory-dashboard-InventoryFunctionRole-XXXXXXXX \
  my-secure-external-id-12345
```

### Example 2: Multiple Accounts (Bulk)
```bash
# Create accounts file
cat > accounts.txt << EOF
111222333444:Production
555666777888:Development
999888777666:Staging
EOF

# Create roles
./scripts/create-bulk-roles.sh \
  123456789012 \
  accounts.txt \
  aws-inventory-dashboard-InventoryFunctionRole-XXXXXXXX \
  my-secure-external-id-12345
```

### Example 3: CloudFormation (Recommended)
```bash
aws cloudformation create-stack \
  --stack-name inventory-read-role \
  --template-body file://member-account-role.yaml \
  --parameters \
    ParameterKey=MainAccountId,ParameterValue=123456789012 \
    ParameterKey=LambdaExecutionRoleName,ParameterValue=aws-inventory-dashboard-InventoryFunctionRole-XXXXXXXX \
    ParameterKey=ExternalId,ParameterValue=my-secure-external-id \
    ParameterKey=RoleName,ParameterValue=InventoryReadRole \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1
```

## Files Reference

| File | Purpose |
|------|---------|
| `create-cross-account-role-complete.sh` | Complete setup (Bash) |
| `create-cross-account-role-complete.ps1` | Complete setup (PowerShell) |
| `create-trust-policy.sh` | Generate trust policy (Bash) |
| `create-trust-policy.ps1` | Generate trust policy (PowerShell) |
| `create-bulk-roles.sh` | Bulk creation (Bash) |
| `policies/inventory-read-policy.json` | Permissions policy |
| `member-account-role.yaml` | CloudFormation template |
| `accounts-example.txt` | Example accounts file |

---

For detailed multi-account setup, see: `MULTI_ACCOUNT_SETUP.md`

