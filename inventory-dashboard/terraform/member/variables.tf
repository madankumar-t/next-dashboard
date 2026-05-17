variable "aws_region" {
  description = "AWS region for this member account deployment"
  type        = string
  default     = "us-east-2"
}

variable "server_account_id" {
  description = "AWS account ID of the server account (dcli_sharedsvcs2). The Lambda execution role in this account will be trusted."
  type        = string
}

variable "server_lambda_role_arn" {
  description = "Full ARN of the Lambda execution role in the server account. Obtain from the server Terraform output 'lambda_execution_role_arn'."
  type        = string
}

variable "role_name" {
  description = "Name of the IAM role to create. Must match the inventory_role_name variable in the server Terraform deployment."
  type        = string
  default     = "InventoryReadRole"
}

variable "external_id" {
  description = "Optional ExternalId condition added to the AssumeRole trust policy. Must match the external_id variable in the server Terraform deployment."
  type        = string
  default     = ""
  sensitive   = true
}

variable "additional_tags" {
  description = "Additional tags to apply to the IAM role"
  type        = map(string)
  default     = {}
}
