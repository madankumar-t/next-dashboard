# External ID Explained

## What is External ID?

**External ID** is an optional security parameter used in AWS cross-account role assumption. It's a shared secret that must be provided when assuming a role, adding an extra layer of security to prevent "confused deputy" attacks.

## Why Use External ID?

### The Problem: Confused Deputy Attack

Without External ID, if someone in Account B knows the role ARN in Account A, they could potentially trick Account A's service into assuming that role, even if Account A didn't intend to grant access to Account B.

**Example Scenario:**
1. Account A (Main) has a Lambda function that assumes roles in member accounts
2. Account B (Malicious) knows Account C's role ARN
3. Account B could potentially trick Account A's Lambda into assuming Account C's role
4. Account B gets unauthorized access to Account C

### The Solution: External ID

External ID acts as a **shared secret** between:
- The **main account** (where Lambda runs)
- The **member account** (where the role exists)

Both must know the same External ID value. This ensures:
- Only entities that know the secret can assume the role
- Prevents unauthorized role assumption
- Adds defense-in-depth security

## How It Works

### 1. In the Trust Policy (Member Account)

The trust policy includes a condition that requires External ID:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::MAIN_ACCOUNT_ID:role/LambdaRole"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "my-secret-external-id-12345"
        }
      }
    }
  ]
}
```

### 2. In the Lambda Function (Main Account)

When assuming the role, the Lambda must provide the same External ID:

```python
sts.assume_role(
    RoleArn='arn:aws:iam::MEMBER_ACCOUNT_ID:role/InventoryReadRole',
    RoleSessionName='InventoryDashboardSession',
    ExternalId='my-secret-external-id-12345'  # Must match trust policy
)
```

### 3. The Flow

```
┌─────────────────┐
│  Main Account   │
│  Lambda Function│
└────────┬────────┘
         │ AssumeRole with ExternalId="secret123"
         ▼
┌─────────────────┐
│  Member Account │
│  Trust Policy   │
│  Checks:        │
│  - Principal ✅ │
│  - ExternalId ✅ │
└─────────────────┘
         │
         ▼
    ✅ Access Granted
```

## Is External ID Required?

**No, External ID is OPTIONAL** but **HIGHLY RECOMMENDED** for production environments.

### Without External ID

```json
{
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::MAIN_ACCOUNT_ID:role/LambdaRole"
  },
  "Action": "sts:AssumeRole"
  // No condition - less secure
}
```

**Pros:**
- Simpler setup
- Easier to test

**Cons:**
- Less secure
- Vulnerable to confused deputy attacks
- Not recommended for production

### With External ID

```json
{
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::MAIN_ACCOUNT_ID:role/LambdaRole"
  },
  "Action": "sts:AssumeRole",
  "Condition": {
    "StringEquals": {
      "sts:ExternalId": "my-secret-external-id-12345"
    }
  }
}
```

**Pros:**
- ✅ More secure
- ✅ Prevents confused deputy attacks
- ✅ AWS best practice
- ✅ Recommended for production

**Cons:**
- Slightly more complex setup
- Must be shared securely between accounts

## How to Generate/Choose External ID

### Option 1: Random String (Recommended)

**Bash:**
```bash
# Generate random External ID
openssl rand -hex 16
# Output: a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6
```

**PowerShell:**
```powershell
# Generate random External ID
-join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | ForEach-Object {[char]$_})
```

**Online:**
- Use a UUID generator: `https://www.uuidgenerator.net/`
- Use a random string generator

### Option 2: Meaningful String

Use a string that's meaningful but hard to guess:
```
aws-inventory-dashboard-2024-prod-secure
company-name-inventory-read-role-2024
```

### Option 3: Combination

Combine account ID with a secret:
```
123456789012-inventory-secret-2024
```

## Best Practices

### 1. Use Strong External IDs
- ✅ At least 16 characters
- ✅ Mix of letters, numbers, and special characters
- ✅ Random or cryptographically secure
- ❌ Don't use predictable values (dates, account IDs alone)

### 2. Store Securely
- ✅ Store in AWS Systems Manager Parameter Store (encrypted)
- ✅ Store in AWS Secrets Manager
- ✅ Set as environment variable in Lambda
- ✅ Pass as CloudFormation parameter
- ❌ Don't hardcode in source code
- ❌ Don't commit to Git

### 3. Rotate Periodically
- Rotate External ID every 90-180 days
- Update in both main account (Lambda) and member accounts (trust policies)
- Coordinate updates to avoid downtime

### 4. Use Different IDs for Different Environments
- Production: `prod-inventory-external-id-xyz123`
- Development: `dev-inventory-external-id-abc456`
- Staging: `staging-inventory-external-id-def789`

## Examples

### Example 1: Using External ID in Script

```bash
# Generate External ID
EXTERNAL_ID=$(openssl rand -hex 16)

# Create trust policy with External ID
./scripts/create-trust-policy.sh \
  123456789012 \
  aws-inventory-dashboard-InventoryFunctionRole-XXXXXXXX \
  "$EXTERNAL_ID" \
  > trust-policy.json

# Create role with trust policy
aws iam create-role \
  --role-name InventoryReadRole \
  --assume-role-policy-document file://trust-policy.json
```

### Example 2: Setting in SAM Template

```yaml
Parameters:
  ExternalId:
    Type: String
    Description: External ID for AssumeRole (security best practice)
    NoEcho: true  # Hides value in console

Globals:
  Function:
    Environment:
      Variables:
        EXTERNAL_ID: !Ref ExternalId
```

Deploy with:
```bash
sam deploy --parameter-overrides ExternalId="my-secret-external-id-12345"
```

### Example 3: Testing Role Assumption

```bash
# Test with External ID
aws sts assume-role \
  --role-arn arn:aws:iam::987654321098:role/InventoryReadRole \
  --role-session-name test-session \
  --external-id my-secret-external-id-12345

# Test without External ID (will fail if External ID is required)
aws sts assume-role \
  --role-arn arn:aws:iam::987654321098:role/InventoryReadRole \
  --role-session-name test-session
  # Error: External ID required
```

## Common Questions

### Q: Can I use the same External ID for all member accounts?

**A:** Yes, but it's more secure to use different IDs per account or environment.

**Recommended:**
- Same External ID for all accounts in same environment (e.g., all prod accounts)
- Different External ID per environment (prod vs dev)

### Q: What happens if External ID doesn't match?

**A:** The `AssumeRole` call will fail with:
```
AccessDenied: User is not authorized to perform: sts:AssumeRole
```

### Q: Can I change External ID after role is created?

**A:** Yes, but you must update:
1. Trust policy in member account
2. Environment variable in main account Lambda
3. Both must match

### Q: Is External ID encrypted?

**A:** No, External ID is sent in plain text in the API call. However:
- It's only used during role assumption
- It's not stored in logs (if configured properly)
- It's a shared secret, not sensitive data itself

### Q: What if I forget the External ID?

**A:** You'll need to:
1. Check Lambda environment variables
2. Check CloudFormation parameters
3. Check trust policy in member account
4. Or regenerate and update both sides

## Summary

| Aspect | Details |
|--------|---------|
| **What** | Optional security parameter for cross-account roles |
| **Purpose** | Prevents confused deputy attacks |
| **Required?** | No, but **highly recommended** for production |
| **Format** | Any string (recommended: 16+ random characters) |
| **Where Used** | Trust policy condition + AssumeRole API call |
| **Best Practice** | Use strong, random values; store securely; rotate periodically |

## Quick Reference

### Generate External ID
```bash
openssl rand -hex 16
```

### Create Trust Policy with External ID
```bash
./scripts/create-trust-policy.sh \
  MAIN_ACCOUNT_ID \
  LAMBDA_ROLE_NAME \
  EXTERNAL_ID \
  > trust-policy.json
```

### Test Role Assumption
```bash
aws sts assume-role \
  --role-arn arn:aws:iam::MEMBER_ACCOUNT_ID:role/InventoryReadRole \
  --role-session-name test \
  --external-id YOUR_EXTERNAL_ID
```

---

For more information, see:
- [AWS Documentation: How to Use External ID](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-user_externalid.html)
- [AWS Security Blog: Confused Deputy Problem](https://aws.amazon.com/blogs/security/how-to-use-external-id-when-granting-access-to-your-aws-resources/)

