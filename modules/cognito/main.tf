resource "aws_cognito_user_pool" "this" {
  name = "${var.name}-portal-users"

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 3
  }

  mfa_configuration = "ON"
  software_token_mfa_configuration {
    enabled = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  user_pool_add_ons {
    advanced_security_mode = "ENFORCED"
  }
}

resource "aws_cognito_user_pool_client" "portal" {
  name            = "${var.name}-portal-client"
  user_pool_id    = aws_cognito_user_pool.this.id
  generate_secret = true

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  allowed_oauth_flows_user_pool_client = true
  supported_identity_providers         = ["COGNITO"]

  callback_urls = var.callback_urls
  logout_urls   = var.logout_urls

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  prevent_user_existence_errors = "ENABLED"
}

# Hosted-UI domain.
#
# REQUIRED by the ALB's authenticate-cognito action: the ALB redirects the
# browser to this domain to run the OIDC code flow, then exchanges the code at
# the token endpoint. Without a domain the listener rule cannot be created.
#
# Cognito prefix domains are globally unique across all AWS accounts, so the
# account id is mixed in to keep it collision-free without needing a custom
# domain (which would want its own ACM cert in us-east-1).
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.name}-${var.domain_suffix}"
  user_pool_id = aws_cognito_user_pool.this.id
}
