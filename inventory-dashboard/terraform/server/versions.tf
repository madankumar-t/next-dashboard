terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }

  # Spacelift manages the backend; configure via workspace environment variables:
  #   TF_VAR_* for input variables
  #   AWS_* for credentials
  # Uncomment and configure for S3 state backend:
  # backend "s3" {
  #   bucket         = "dcli-terraform-state"
  #   key            = "inventory-dashboard/server/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "dcli-terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# WAF for CloudFront must be deployed in us-east-1 regardless of primary region
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}
