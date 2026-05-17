# Multi-Account Setup - Quick Reference

## Summary

Your dashboard needs access to these member accounts:
- **090130567842**
- **780781249373**
- **014402785795**
- **196690901583**

Main Account: **964201074108**

## Step-by-Step Process

### For Each Member Account:

1. **Switch to the member account**
   ```powershell
   # Configure AWS CLI for the member account
   aws configure --profile member-account-name
   # Or set environment variables
   $env:AWS_PROFILE="member-account-name"
   ```

2. **Run the setup script**
   
   **PowerShell:**
   ```powershell
   cd d:\NexTurn\mydashboard-main\scripts
   .\setup-member-account.ps1
   ```
   
   **Bash/Linux:**
   ```bash
   cd /path/to/mydashboard-main/scripts
   chmod +x setup-member-account.sh
   ./setup-member-account.sh
   ```

3. **Verify the role was created**
   ```powershell
   aws iam get-role --role-name InventoryReadRole --query "Role.Arn" --output text
   ```
   
   Expected output:
   ```
   arn:aws:iam::ACCOUNT_ID:role/InventoryReadRole
   ```

4. **Repeat for next account**
   Switch AWS profile and run step 2 again

### Manual Setup (If Script Fails)

If the automated script doesn't work, you can deploy manually:

```powershell
aws cloudformation create-stack \
    --stack-name inventory-dashboard-member-role \
    --template-body file://member-account-role.yaml \
    --parameters \
        ParameterKey=MainAccountId,ParameterValue=964201074108 \
        ParameterKey=LambdaExecutionRoleName,ParameterValue=inventory-dashboard-RefreshFunctionRole-zoovJCpyuZXf \
        ParameterKey=RoleName,ParameterValue=InventoryReadRole \
    --capabilities CAPABILITY_NAMED_IAM \
    --region us-east-1
```

## After All Accounts Are Configured

### Test the Setup

1. **Access your dashboard**
   - https://d1mytjoejextnh.cloudfront.net
   - Login with your Azure AD credentials

2. **Trigger inventory collection**
   - Click "Refresh" button
   - Select service (EC2, S3, RDS, etc.)
   - Wait for collection to complete

3. **Check CloudWatch Logs**
   ```powershell
   aws logs tail /aws/lambda/inventory-dashboard-RefreshFunction-q7H9d6aYqn5t --follow
   ```
   
   You should see successful role assumptions instead of AccessDenied errors

### Verify Data in DynamoDB

```powershell
# Check if data was collected
aws dynamodb scan --table-name aws-inventory-data --select COUNT --output json

# Check metadata
aws dynamodb scan --table-name aws-inventory-metadata --output json
```

## Troubleshooting

### "AccessDenied" when assuming role

**Problem:** Lambda can't assume the InventoryReadRole

**Solutions:**
1. Verify the role exists in the member account:
   ```powershell
   aws iam get-role --role-name InventoryReadRole
   ```

2. Check the trust policy allows the Lambda role:
   ```powershell
   aws iam get-role --role-name InventoryReadRole --query "Role.AssumeRolePolicyDocument"
   ```
   
   Should include:
   ```json
   {
     "Principal": {
       "AWS": "arn:aws:iam::964201074108:role/inventory-dashboard-RefreshFunctionRole-zoovJCpyuZXf"
     }
   }
   ```

3. Verify the Lambda role has sts:AssumeRole permission:
   ```powershell
   aws iam get-role-policy \
       --role-name inventory-dashboard-RefreshFunctionRole-zoovJCpyuZXf \
       --policy-name <policy-name>
   ```

### No resources showing up

1. **Check the Lambda logs:**
   ```powershell
   aws logs tail /aws/lambda/inventory-dashboard-RefreshFunction-q7H9d6aYqn5t --since 10m
   ```

2. **Manually trigger a refresh:**
   - Use the dashboard UI
   - Or invoke Lambda directly

3. **Verify DynamoDB tables:**
   ```powershell
   aws dynamodb list-tables --query "TableNames[?contains(@, 'inventory')]"
   ```

### Role already exists error

If the role already exists but needs updating:

```powershell
aws cloudformation update-stack \
    --stack-name inventory-dashboard-member-role \
    --template-body file://member-account-role.yaml \
    --parameters \
        ParameterKey=MainAccountId,ParameterValue=964201074108 \
        ParameterKey=LambdaExecutionRoleName,ParameterValue=inventory-dashboard-RefreshFunctionRole-zoovJCpyuZXf \
        ParameterKey=RoleName,ParameterValue=InventoryReadRole \
    --capabilities CAPABILITY_NAMED_IAM \
    --region us-east-1
```

## Quick Commands Reference

### Switch AWS Profile
```powershell
# PowerShell
$env:AWS_PROFILE="profile-name"

# Bash
export AWS_PROFILE=profile-name
```

### Verify Current Account
```powershell
aws sts get-caller-identity
```

### List All Profiles
```powershell
aws configure list-profiles
```

### Deploy Role (One Command)
```powershell
aws cloudformation create-stack --stack-name inventory-dashboard-member-role --template-body file://member-account-role.yaml --parameters ParameterKey=MainAccountId,ParameterValue=964201074108 ParameterKey=LambdaExecutionRoleName,ParameterValue=inventory-dashboard-RefreshFunctionRole-zoovJCpyuZXf ParameterKey=RoleName,ParameterValue=InventoryReadRole --capabilities CAPABILITY_NAMED_IAM --region us-east-1
```

## Timeline

- **Per account setup:** ~2-3 minutes
- **Total for 4 accounts:** ~10-15 minutes
- **First data collection:** ~5-10 minutes (depending on resources)

## Security Notes

- ✅ Roles use least-privilege permissions (read-only)
- ✅ Cross-account access via IAM role assumption
- ✅ No credentials stored or shared
- ⚠️ Consider using External ID for additional security
- ⚠️ Audit CloudTrail logs for role assumption activity

## Need Help?

Check these files:
- [MULTI_ACCOUNT_SETUP.md](../MULTI_ACCOUNT_SETUP.md) - Detailed setup guide
- [MULTI_ACCOUNT_SUMMARY.md](../MULTI_ACCOUNT_SUMMARY.md) - Architecture overview
- [member-account-role.yaml](../member-account-role.yaml) - CloudFormation template
