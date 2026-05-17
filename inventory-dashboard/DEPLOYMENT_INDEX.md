# AWS Inventory Dashboard - Deployment Documentation Index

## 📋 Start Here

**Just want to deploy?** Start with one of these:

1. **[QUICK_DEPLOY.md](QUICK_DEPLOY.md)** ⚡ - Quick commands (5-minute reference)
2. **[DEPLOYMENT_SCRIPTS.md](DEPLOYMENT_SCRIPTS.md)** 💻 - Platform-specific scripts (Windows PowerShell & Linux Bash)
3. **[DEPLOYMENT_INSTRUCTIONS.md](DEPLOYMENT_INSTRUCTIONS.md)** 📖 - Full step-by-step guide with explanations

---

## 📚 Documentation Map

### Core Deployment Guides

| Document | Best For | Time | Audience |
|----------|----------|------|----------|
| [QUICK_DEPLOY.md](QUICK_DEPLOY.md) | Quick command reference | 5 min | Experienced AWS users |
| [DEPLOYMENT_SCRIPTS.md](DEPLOYMENT_SCRIPTS.md) | Platform-specific commands | 10 min | Windows/Linux users |
| [DEPLOYMENT_INSTRUCTIONS.md](DEPLOYMENT_INSTRUCTIONS.md) | Complete walkthrough | 30 min | First-time deployers |
| [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) | Detailed architecture & troubleshooting | 45 min | Advanced setup |

### Specialized Guides

| Document | Topic | Read When |
|----------|-------|-----------|
| [MULTI_ACCOUNT_QUICK_START.md](MULTI_ACCOUNT_QUICK_START.md) | Quick multi-account setup | Setting up member accounts |
| [MULTI_ACCOUNT_SETUP.md](MULTI_ACCOUNT_SETUP.md) | Detailed multi-account guide | Complex cross-account scenarios |
| [frontend/FRONTEND_DEPLOYMENT.md](frontend/FRONTEND_DEPLOYMENT.md) | Frontend-specific deployment | Frontend issues or updates |
| [frontend/LOCAL_DEVELOPMENT.md](frontend/LOCAL_DEVELOPMENT.md) | Local development setup | Development work |
| [backend/README_PYTHON_VERSION.md](backend/README_PYTHON_VERSION.md) | Python environment info | Python-related issues |

### Infrastructure Templates

| File | Purpose |
|------|---------|
| [backend/template.yaml](backend/template.yaml) | SAM template for Lambda, API Gateway, DynamoDB |
| [member-account-role.yaml](member-account-role.yaml) | CloudFormation template for member account roles |
| [frontend/frontend-infrastructure.yaml](frontend/frontend-infrastructure.yaml) | CloudFormation for S3 + CloudFront |

### Deployment Scripts

| Script | Location | Purpose |
|--------|----------|---------|
| `deploy-all.sh` / `deploy-all.ps1` | `scripts/` | Master deployment (all phases) |
| `deploy-backend-main-account.sh` / `.ps1` | `scripts/` | Backend deployment only |
| `deploy-frontend-main-account.sh` / `.ps1` | `scripts/` | Frontend deployment only |
| `create-cross-account-role-complete.sh` / `.ps1` | `scripts/` | Create member account roles |
| `setup_layer.sh` | `backend/` | Python layer setup |

---

## 🚀 Quick Start Paths

### Path 1: First-Time Full Deployment (30 minutes)

1. **Prepare** (5 min)
   - Install [prerequisites](#prerequisites)
   - Get AWS account IDs
   - Configure AWS credentials

2. **Read** (5 min)
   - [DEPLOYMENT_INSTRUCTIONS.md](DEPLOYMENT_INSTRUCTIONS.md) - Read sections 1-3

3. **Deploy** (20 min)
   - Follow [DEPLOYMENT_INSTRUCTIONS.md](DEPLOYMENT_INSTRUCTIONS.md)
   - Run scripts for: Backend → Member Accounts → Frontend
   - Or use: `./deploy-all.sh --skip-confirmation`

### Path 2: Experienced AWS Users (10 minutes)

1. **Reference** [QUICK_DEPLOY.md](QUICK_DEPLOY.md)
2. **Run appropriate commands** for your OS
3. **Verify** with provided verification commands

### Path 3: Troubleshooting (varies)

1. **Check** [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) → Troubleshooting section
2. **Run debug commands** from [QUICK_DEPLOY.md](QUICK_DEPLOY.md) → Troubleshooting
3. **Reference** [MULTI_ACCOUNT_SETUP.md](MULTI_ACCOUNT_SETUP.md) for account issues

### Path 4: Update Existing Deployment (varies)

1. **Backend only**: `cd backend && sam deploy --guided`
2. **Frontend only**: `cd frontend && npm run build && npm run deploy`
3. **Add member account**: Run member account role creation script
4. **Everything**: `./deploy-all.sh`

---

## 📊 Deployment Overview

### 3 Deployment Phases

```
Phase 1: BACKEND (Main Account)
├── Lambda Function
├── API Gateway
├── DynamoDB
└── IAM Execution Role
   ↓
Phase 2: MEMBER ACCOUNTS
├── IAM ReadOnly Role (per account)
└── Trust Policy (allows Phase 1 Lambda to assume)
   ↓
Phase 3: FRONTEND (Main Account)
├── S3 Bucket
├── CloudFront Distribution
├── Lambda@Edge (optional)
└── Cognito Integration
```

### Estimated Time & Resources

| Phase | Duration | AWS Services | Cost |
|-------|----------|--------------|------|
| Backend | 5-10 min | Lambda, API Gateway, DynamoDB | Low (~$5/month) |
| Member Accounts | 2-3 min each | IAM | Free |
| Frontend | 3-5 min | S3, CloudFront | Low (~$10-20/month) |
| **Total** | **10-20 min** | **7+ services** | **~$20-30/month** |

---

## ✅ Prerequisites Checklist

Before deploying, ensure you have:

- [ ] **AWS Account(s)** - 1 main + multiple member accounts
- [ ] **AWS CLI v2** - Installed and configured (`aws --version`)
- [ ] **SAM CLI** - Installed (`sam --version`)
- [ ] **Node.js 18+** - Installed (`node --version`)
- [ ] **npm** - Installed (`npm --version`)
- [ ] **Python 3.12** - Installed (`python --version`)
- [ ] **AWS Credentials** - Configured (`aws sts get-caller-identity`)
- [ ] **IAM Permissions** - CloudFormation, Lambda, EC2, S3, DynamoDB, IAM, CloudFront
- [ ] **Cognito User Pool** - Already exists or ready to create
- [ ] **Account IDs** - Main and member account IDs noted

---

## 🔍 Script Selection Guide

**I want to deploy...**

| Goal | Windows | Linux/macOS |
|------|---------|------------|
| Everything (1 command) | `.\deploy-all.ps1` | `./deploy-all.sh` |
| Backend only | `.\deploy-backend-main-account.ps1` | `./deploy-backend-main-account.sh` |
| Frontend only | `.\deploy-frontend-main-account.ps1` | `./deploy-frontend-main-account.sh` |
| Member account role | `.\create-cross-account-role-complete.ps1` | `./create-cross-account-role-complete.sh` |
| Everything manually | See [DEPLOYMENT_INSTRUCTIONS.md](DEPLOYMENT_INSTRUCTIONS.md) | See [DEPLOYMENT_INSTRUCTIONS.md](DEPLOYMENT_INSTRUCTIONS.md) |

---

## 🎯 Key Commands Quick Reference

```bash
# All-in-one (recommended for first deploy)
./deploy-all.sh --skip-confirmation

# Individual components
./deploy-backend-main-account.sh --profile main --region us-east-1
./deploy-frontend-main-account.sh --api-url https://xxx.execute-api.us-east-1.amazonaws.com/dev
./create-cross-account-role-complete.sh MEMBER_ID MAIN_ID

# Verification
aws cloudformation describe-stacks --stack-name inventory-dashboard --query "Stacks[0].StackStatus"
aws logs tail /aws/lambda/inventory-dashboard-RefreshFunction --follow

# Cleanup
aws cloudformation delete-stack --stack-name inventory-dashboard
aws cloudformation delete-stack --stack-name aws-inventory-dashboard-frontend
```

---

## 📝 Configuration Files

### Environment Variables (Frontend)

**File**: `frontend/.env.local`

```env
NEXT_PUBLIC_API_URL=https://your-api-endpoint
NEXT_PUBLIC_COGNITO_USER_POOL_ID=region_pool_id
NEXT_PUBLIC_COGNITO_CLIENT_ID=client_id
NEXT_PUBLIC_COGNITO_REGION=region
NEXT_PUBLIC_COGNITO_DOMAIN=domain
```

### SAM Configuration (Backend)

**File**: `backend/samconfig.toml`

```toml
[default.deploy]
region = "us-east-1"
s3_bucket = "deployment-bucket"
parameter_overrides = "InventoryAccounts=id1:name1,id2:name2"
```

### Script Parameters

See [DEPLOYMENT_SCRIPTS.md](DEPLOYMENT_SCRIPTS.md) → "Script Parameters" section

---

## 🔐 Security Considerations

1. **External ID** - Use for production deployments
2. **Least Privilege** - Member roles only have ReadOnly permissions
3. **Cognito** - Use existing user pool or create new one
4. **CloudFront** - Caches frontend (can be invalidated)
5. **API Gateway** - Requires Cognito authentication
6. **Lambda** - Executes with defined IAM role

See [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for security details.

---

## 🐛 Common Issues & Solutions

| Issue | Solution | Reference |
|-------|----------|-----------|
| "Access Denied" | Check IAM permissions and AWS credentials | [DEPLOYMENT_GUIDE.md#troubleshooting](DEPLOYMENT_GUIDE.md#troubleshooting) |
| "Role not found" | Create member account role first | [DEPLOYMENT_INSTRUCTIONS.md#phase-2](DEPLOYMENT_INSTRUCTIONS.md#phase-2-member-account-setup) |
| "API not responding" | Check Lambda logs and API Gateway settings | [QUICK_DEPLOY.md#troubleshooting](QUICK_DEPLOY.md#troubleshooting-commands) |
| "Frontend shows errors" | Update .env.local and clear CloudFront cache | [frontend/FRONTEND_DEPLOYMENT.md](frontend/FRONTEND_DEPLOYMENT.md) |
| "Lambda timeout" | Check Lambda execution role and permissions | [MULTI_ACCOUNT_SETUP.md](MULTI_ACCOUNT_SETUP.md) |

---

## 📞 Getting Help

1. **Quick Questions** → [QUICK_DEPLOY.md](QUICK_DEPLOY.md) or [QUICK_REFERENCE.md](QUICK_DEPLOY.md)
2. **Deployment Help** → [DEPLOYMENT_INSTRUCTIONS.md](DEPLOYMENT_INSTRUCTIONS.md)
3. **Technical Issues** → [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) + Troubleshooting
4. **Scripts Help** → [DEPLOYMENT_SCRIPTS.md](DEPLOYMENT_SCRIPTS.md)
5. **Multi-Account** → [MULTI_ACCOUNT_SETUP.md](MULTI_ACCOUNT_SETUP.md)
6. **Frontend Issues** → [frontend/FRONTEND_DEPLOYMENT.md](frontend/FRONTEND_DEPLOYMENT.md)

---

## 📦 Project Structure

```
inventory-dashboard/
├── DEPLOYMENT_INSTRUCTIONS.md    ← Full step-by-step guide (YOU ARE HERE)
├── QUICK_DEPLOY.md               ← Quick commands reference
├── DEPLOYMENT_SCRIPTS.md         ← Platform-specific scripts
├── DEPLOYMENT_GUIDE.md           ← Original detailed guide
├── MULTI_ACCOUNT_SETUP.md        ← Multi-account setup details
├── member-account-role.yaml      ← CF template for member roles
│
├── backend/
│   ├── template.yaml             ← SAM template (Lambda, API, DynamoDB)
│   ├── samconfig.toml            ← SAM configuration
│   ├── requirements.txt          ← Python dependencies
│   └── src/
│       ├── app.py                ← Lambda handler
│       └── collectors/           ← Resource collectors
│
├── frontend/
│   ├── FRONTEND_DEPLOYMENT.md    ← Frontend deployment guide
│   ├── frontend-infrastructure.yaml ← CF template (S3, CloudFront)
│   ├── .env.local.example        ← Environment template
│   ├── package.json              ← Node dependencies
│   └── src/                      ← Next.js app source
│
└── scripts/
    ├── deploy-all.sh/.ps1        ← Master deployment script
    ├── deploy-backend-main-account.sh/.ps1
    ├── deploy-frontend-main-account.sh/.ps1
    ├── create-cross-account-role-complete.sh/.ps1
    └── policies/
        └── inventory-read-policy.json ← IAM policy for member roles
```

---

## ✨ Next Steps After Deployment

1. ✅ **Verify Deployment** - Run verification commands
2. ✅ **Access Frontend** - Open CloudFront URL
3. ✅ **Login** - Use Cognito credentials
4. ✅ **View Inventory** - Check dashboard loads data
5. ✅ **Test Cross-Account** - Verify multi-account resource viewing
6. ✅ **Configure Alerts** - Set up CloudWatch alarms
7. ✅ **Enable Logging** - Configure CloudFront and API Gateway logs
8. ✅ **Schedule Refresh** - Set up Lambda execution schedule
9. ✅ **Document APIs** - Share API endpoint with team
10. ✅ **Monitor Costs** - Set up AWS budget alerts

---

## 📊 Document Usage Statistics

| Document | Purpose | Read Time | Readers |
|----------|---------|-----------|---------|
| [QUICK_DEPLOY.md](QUICK_DEPLOY.md) | Quick reference | 5 min | Experienced users |
| [DEPLOYMENT_SCRIPTS.md](DEPLOYMENT_SCRIPTS.md) | Script-specific help | 10 min | Platform-specific help |
| [DEPLOYMENT_INSTRUCTIONS.md](DEPLOYMENT_INSTRUCTIONS.md) | Complete guide | 30 min | First-time deployers |
| [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) | Deep dive | 45 min | Advanced troubleshooting |
| [MULTI_ACCOUNT_SETUP.md](MULTI_ACCOUNT_SETUP.md) | Multi-account details | 20 min | Cross-account users |

---

## 🎓 Learning Path

**Beginner:**
1. Read [DEPLOYMENT_INSTRUCTIONS.md](DEPLOYMENT_INSTRUCTIONS.md) - Section 1-3
2. Run `./deploy-all.sh --skip-confirmation`
3. Verify with provided commands

**Intermediate:**
1. Read [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)
2. Understand architecture and deployment phases
3. Run individual scripts for each phase
4. Troubleshoot issues with [DEPLOYMENT_GUIDE.md#troubleshooting](DEPLOYMENT_GUIDE.md#troubleshooting)

**Advanced:**
1. Review [MULTI_ACCOUNT_SETUP.md](MULTI_ACCOUNT_SETUP.md)
2. Understand IAM policies and cross-account access
3. Customize SAM template and CloudFormation templates
4. Set up advanced monitoring and logging

---

## ❓ Frequently Asked Questions

**Q: How long does deployment take?**
A: 10-20 minutes total (backend 5-10 min, roles 2-3 min each, frontend 3-5 min)

**Q: Do I need multiple AWS accounts?**
A: No, but it's recommended. Single account works too.

**Q: Can I deploy to a region other than us-east-1?**
A: Yes, specify with `--region us-west-2` in scripts

**Q: What AWS services are used?**
A: Lambda, API Gateway, DynamoDB, S3, CloudFront, CloudWatch, IAM, Cognito

**Q: How much does it cost?**
A: ~$20-30/month (depends on usage and data size)

**Q: Can I use an existing Cognito User Pool?**
A: Yes, specify IDs in `.env.local` and script parameters

**Q: How do I update after deployment?**
A: Re-run deploy scripts for changed components or use `sam deploy --guided`

**Q: How do I add more member accounts later?**
A: Run member account role creation script for new accounts

---

## 🔄 Document Versions

- **Version 1.0** - Initial deployment guides
- **Version 1.1** - Added platform-specific scripts guide
- **Version 1.2** - Added quick deployment reference
- **Version 1.3** - Added this index document

Last Updated: May 9, 2026

---

## 📥 Start Deploying Now

Choose your path:

1. **First-time?** → [DEPLOYMENT_INSTRUCTIONS.md](DEPLOYMENT_INSTRUCTIONS.md)
2. **Experienced?** → [QUICK_DEPLOY.md](QUICK_DEPLOY.md)
3. **Need scripts?** → [DEPLOYMENT_SCRIPTS.md](DEPLOYMENT_SCRIPTS.md)
4. **Troubleshooting?** → [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)
5. **Multi-account?** → [MULTI_ACCOUNT_SETUP.md](MULTI_ACCOUNT_SETUP.md)

---

**Good luck with your deployment! 🚀**
