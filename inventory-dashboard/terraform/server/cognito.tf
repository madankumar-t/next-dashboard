####################################################################
# Cognito User Pool
####################################################################
resource "aws_cognito_user_pool" "main" {
  name = "${local.name_prefix}-users"

  # Username is the email address
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  admin_create_user_config {
    allow_admin_create_user_only = !var.cognito_allow_self_signup
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  mfa_configuration = "OPTIONAL"

  software_token_mfa_configuration {
    enabled = true
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 5
      max_length = 254
    }
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
}

####################################################################
# Cognito User Pool Client (used by the Next.js frontend)
####################################################################
resource "aws_cognito_user_pool_client" "frontend" {
  name         = "${local.name_prefix}-frontend"
  user_pool_id = aws_cognito_user_pool.main.id

  # SPA uses the hosted UI authorization code flow – no client secret
  generate_secret = false

  # ── OAuth / Hosted UI ─────────────────────────────────────────
  # Required for the Hosted UI redirect flow used by the frontend.
  # callback_urls MUST exactly match the redirect_uri sent by the app.
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]
  supported_identity_providers         = ["COGNITO"]

  # Allow both the CloudFront domain and the custom domain (when set).
  # Terraform resolves aws_cloudfront_distribution.frontend.domain_name
  # at apply time, so the dependency is wired automatically.
  callback_urls = concat(
    ["https://${aws_cloudfront_distribution.frontend.domain_name}/auth/callback"],
    var.custom_domain_name != "" ? ["https://${var.custom_domain_name}/auth/callback"] : []
  )

  logout_urls = concat(
    ["https://${aws_cloudfront_distribution.frontend.domain_name}/"],
    var.custom_domain_name != "" ? ["https://${var.custom_domain_name}/"] : []
  )

  # ── Direct auth flows (kept for admin / testing use-cases) ────
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
  ]

  # Tokens expire after sensible defaults
  access_token_validity  = 1   # hours
  id_token_validity      = 1   # hours
  refresh_token_validity = 30  # days

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  prevent_user_existence_errors = "ENABLED"
}

####################################################################
# Cognito User Pool Domain (for hosted UI sign-in page)
####################################################################
resource "aws_cognito_user_pool_domain" "main" {
  domain       = local.name_prefix
  user_pool_id = aws_cognito_user_pool.main.id
}
