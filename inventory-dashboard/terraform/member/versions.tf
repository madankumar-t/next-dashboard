terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Spacelift manages backend state; configure via workspace environment variables.
  # Example S3 backend:
  # backend "s3" {
  #   bucket         = "dcli-terraform-state"
  #   key            = "inventory-dashboard/member/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "dcli-terraform-locks"
  #   encrypt        = true
  # }
}

# Deploy into the member account using credentials injected by Spacelift
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "inventory-dashboard"
      ManagedBy   = "terraform"
      ServerAccount = var.server_account_id
    }
  }
}
