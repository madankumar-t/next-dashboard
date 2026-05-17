# Troubleshooting AccessDenied Errors for Cross-Account Roles

## Error Message

```
AccessDenied: User: arn:aws:sts::964201074108:assumed-role/inventory-dashboard-RefreshFunctionRole-HBhjOShWl5YR/inventory-dashboard-RefreshFunction-ox4DeJBH5N9R
is not authorized to perform: sts:AssumeRole on resource: arn:aws:iam::090130567842:role/InventoryReadRole
```

## What This Means

The Lambda function in the **main account** (964201074108) is trying to assume a role in the **member account** (090130567842), but the trust policy in the member account doesn't allow it.

## Root Causes

### 1. Trust Policy Principal Mismatch ⚠️ Most Common

**Problem:** The trust policy in member account doesn't allow the Lambda execution role.

**Solution:** Update trust policy to allow the correct Lambda role ARN.

**From your error:**
- Main Account: `964201074108`
- Lambda Role: `inventory-dashboard-RefreshFunctionRole-HBhjOShWl5YR`
- Member Account: `090130567842`
- Role Name: `InventoryReadRole`

**Correct Principal ARN should be:**
```
arn:aws:iam::964201074108:role/inventory-dashboard-RefreshFunctionRole-HBhjOShWl5YR
```

### 2. External ID Mismatch

**Problem:** Trust policy requires External ID, but Lambda doesn't provide it (or provides wrong one).

**Solution:** Ensure External ID matches in both places.

### 3. Role Doesn't Exist

**Problem:** The role `InventoryReadRole` doesn't exist in member account.

**Solution:** Create the role first.

## Quick Fix Script

### Option 1: Use Diagnostic Script

**Bash:**
```bash
chmod +x scripts/fix-trust-policy-issue.sh
./scripts/fix-trust-policy-issue.sh \
  090130567842 \
  964201074108 \
  inventory-dashboard-RefreshFunctionRole-HBhjOShWl5YR \
  YOUR_EXTERNAL_ID
```

**PowerShell:**
```powershell
.\scripts\fix-trust-policy-issue.ps1 \
  -MemberAccountId 090130567842 \
  -MainAccountId 964201074108 \
  -LambdaRoleName inventory-dashboard-RefreshFunctionRole-HBhjOShWl5YR \
  -ExternalId YOUR_EXTERNAL_ID
```

### Option 2: Manual Fix

#### Step 1: Get Current Trust Policy

```bash
aws iam get-role \
  --role-name InventoryReadRole \
  --query 'Role.AssumeRolePolicyDocument' \
  --output json > current-trust-policy.json
```

#### Step 2: Create Correct Trust Policy

```bash
./scripts/create-trust-policy.sh \
  964201074108 \
  inventory-dashboard-RefreshFunctionRole-HBhjOShWl5YR \
  YOUR_EXTERNAL_ID \
  > correct-trust-policy.json
```

#### Step 3: Update Trust Policy

```bash
aws iam update-assume-role-policy \
  --role-name InventoryReadRole \
  --policy-document file://correct-trust-policy.json
```

## Step-by-Step Diagnosis

### Step 1: Verify Role Exists

```bash
# In member account (090130567842)
aws iam get-role --role-name InventoryReadRole
```

**If role doesn't exist:**
```bash
# Create it using the complete script
./scripts/create-cross-account-role-complete.sh \
  090130567842 \
  964201074108 \
  inventory-dashboard-RefreshFunctionRole-HBhjOShWl5YR \
  YOUR_EXTERNAL_ID
```

### Step 2: Check Current Trust Policy

```bash
aws iam get-role \
  --role-name InventoryReadRole \
  --query 'Role.AssumeRolePolicyDocument' \
  --output json | jq '.'
```

**Check:**
- ✅ Principal ARN should be: `arn:aws:iam::964201074108:role/inventory-dashboard-RefreshFunctionRole-HBhjOShWl5YR`
- ✅ Or: `arn:aws:iam::964201074108:root` (less secure)
- ✅ External ID condition (if using)

### Step 3: Verify Lambda External ID

```bash
# In main account (964201074108)
aws lambda get-function-configuration \
  --function-name inventory-dashboard-RefreshFunction \
  --query 'Environment.Variables.EXTERNAL_ID' \
  --output text
```

**Must match** the External ID in the trust policy (if using).

### Step 4: Test Role Assumption

```bash
# From main account, test assuming the role
aws sts assume-role \
  --role-arn arn:aws:iam::090130567842:role/InventoryReadRole \
  --role-session-name test-session \
  --external-id YOUR_EXTERNAL_ID  # If using External ID
```

**If this fails**, the trust policy is incorrect.

## Common Issues & Solutions

### Issue 1: Wrong Principal ARN

**Symptom:** Trust policy has wrong account ID or role name.

**Fix:**
```bash
# Generate correct trust policy
./scripts/create-trust-policy.sh \
  964201074108 \
  inventory-dashboard-RefreshFunctionRole-HBhjOShWl5YR \
  YOUR_EXTERNAL_ID \
  > trust-policy.json

# Update role
aws iam update-assume-role-policy \
  --role-name InventoryReadRole \
  --policy-document file://trust-policy.json
```

### Issue 2: External ID Mismatch

**Symptom:** Trust policy requires External ID, but Lambda doesn't provide it.

**Check Lambda:**
```bash
aws lambda get-function-configuration \
  --function-name inventory-dashboard-RefreshFunction \
  --query 'Environment.Variables' \
  --output json
```

**Fix:**
1. If External ID is missing in Lambda, add it:
   ```bash
   aws lambda update-function-configuration \
     --function-name inventory-dashboard-RefreshFunction \
     --environment "Variables={EXTERNAL_ID=your-external-id,...}"
   ```

2. Or remove External ID from trust policy (less secure):
   ```bash
   ./scripts/create-trust-policy.sh \
     964201074108 \
     inventory-dashboard-RefreshFunctionRole-HBhjOShWl5YR \
     > trust-policy.json  # No External ID
   ```

### Issue 3: Role Doesn't Exist

**Symptom:** `NoSuchEntity` error when getting role.

**Fix:** Create the role:
```bash
./scripts/create-cross-account-role-complete.sh \
  090130567842 \
  964201074108 \
  inventory-dashboard-RefreshFunctionRole-HBhjOShWl5YR \
  YOUR_EXTERNAL_ID
```

### Issue 4: Using Account Root Instead of Specific Role

**Symptom:** Trust policy uses `arn:aws:iam::ACCOUNT_ID:root` instead of specific role.

**Current (Less Secure):**
```json
{
  "Principal": {
    "AWS": "arn:aws:iam::964201074108:root"
  }
}
```

**Should Be (More Secure):**
```json
{
  "Principal": {
    "AWS": "arn:aws:iam::964201074108:role/inventory-dashboard-RefreshFunctionRole-HBhjOShWl5YR"
  }
}
```

**Fix:** Use the complete setup script with Lambda role name.

## Verification Checklist

After fixing, verify:

- [ ] Role exists in member account
- [ ] Trust policy principal matches Lambda role ARN
- [ ] External ID matches (if using)
- [ ] Lambda has External ID in environment variables (if using)
- [ ] Test role assumption succeeds
- [ ] CloudWatch logs show successful assumption

## Quick Reference

### Your Specific Values

Based on the error:
- **Main Account:** `964201074108`
- **Lambda Role:** `inventory-dashboard-RefreshFunctionRole-HBhjOShWl5YR`
- **Member Account:** `090130567842`
- **Role Name:** `InventoryReadRole`

### Correct Trust Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::964201074108:role/inventory-dashboard-RefreshFunctionRole-HBhjOShWl5YR"
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

### Quick Fix Command

```bash
# Generate and apply correct trust policy
./scripts/create-trust-policy.sh \
  964201074108 \
  inventory-dashboard-RefreshFunctionRole-HBhjOShWl5YR \
  YOUR_EXTERNAL_ID \
  > trust-policy.json

aws iam update-assume-role-policy \
  --role-name InventoryReadRole \
  --policy-document file://trust-policy.json
```

## Still Having Issues?

1. **Check IAM permissions** - Ensure you have permission to update roles in member account
2. **Check CloudTrail** - Look for detailed error messages
3. **Verify account IDs** - Double-check all account IDs are correct
4. **Check for typos** - Role names and ARNs must match exactly

---

For more help, see: `CROSS_ACCOUNT_ROLE_SETUP.md`

