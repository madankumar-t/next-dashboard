locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = merge({
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.additional_tags)

  has_custom_domain = var.custom_domain_name != ""

  # Path from terraform/server/ to the application source
  backend_src_path  = "${path.root}/../../backend/src"
  backend_root_path = "${path.root}/../../backend"
  build_path        = "${path.root}/build"
}
