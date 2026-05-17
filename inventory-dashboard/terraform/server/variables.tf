variable "aws_region" {
  description = "Primary AWS region for deployment"
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "server_account_id" {
  description = "Optional override for the AWS account ID for the server account. Prefer deriving this from the active AWS credentials/provider configuration where needed."
  type        = string
  default     = null
}

variable "project_name" {
  description = "Project identifier used for resource naming and tagging"
  type        = string
  default     = "inventory-dashboard"
}

variable "inventory_role_name" {
  description = "Name of the IAM role that must exist in each member account for cross-account access"
  type        = string
  default     = "InventoryReadRole"
}

variable "inventory_accounts" {
  description = "Comma-separated member account IDs to collect inventory from. Format: accountId1:Name1,accountId2:Name2 or bare accountId1,accountId2"
  type        = string
  default     = ""
}

variable "inventory_regions" {
  description = "Comma-separated list of AWS regions to collect inventory from. Defaults to DCLI's five active regions. All other regions are blocked by SCPs and must not be queried."
  type        = string
  default     = "us-east-1,us-east-2,us-west-2,ap-south-1,sa-east-1"
}

variable "external_id" {
  description = "Optional ExternalId condition for STS AssumeRole calls into member accounts (recommended for security)"
  type        = string
  default     = ""
  sensitive   = true
}

# ── Cognito ──────────────────────────────────────────────────────────────────

variable "cognito_allow_self_signup" {
  description = "Allow end-users to self-register in the Cognito User Pool"
  type        = bool
  default     = false
}

# ── Frontend / CloudFront ─────────────────────────────────────────────────────

variable "frontend_bucket_name" {
  description = "Globally-unique S3 bucket name for the Next.js static frontend"
  type        = string
  default     = "dcli-inventory-dashboard-frontend"
}

variable "allowed_ip_cidrs" {
  description = "CIDR blocks allowed through the CloudFront WAF. All other IPs are blocked."
  type        = list(string)
  default     = ["107.138.107.196/32"]
}

variable "waf_rate_limit" {
  description = "Maximum requests per IP per 5-minute window before WAF blocks the IP. Applies after the IP allowlist check."
  type        = number
  default     = 1000
}

variable "custom_domain_name" {
  description = "Optional custom domain for the CloudFront distribution (e.g. dashboard.dcli.com)"
  type        = string
  default     = ""
}

variable "acm_certificate_arn" {
  # Cross-variable validation (custom_domain_name != "" → this must be set) is enforced
  # via a lifecycle precondition in cloudfront.tf – Terraform does not allow variable
  # validation blocks to reference other variables.
  description = "ACM certificate ARN in us-east-1 for the custom domain (required when custom_domain_name is set)"
  type        = string
  default     = ""

}

# ── Scheduling / Operations ──────────────────────────────────────────────────

variable "refresh_schedule_expression" {
  description = "EventBridge cron/rate expression for the automated inventory refresh"
  type        = string
  default     = "cron(0 */6 * * ? *)"
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 30
}

# ── Tagging ──────────────────────────────────────────────────────────────────

variable "additional_tags" {
  description = "Additional tags merged onto all resources"
  type        = map(string)
  default     = {}
}
