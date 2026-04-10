############################
# Cognito Authentication
############################

resource "aws_cognito_user_pool" "frontend_auth" {
  name              = "${var.project_name}-users"
  mfa_configuration = "OFF"
  admin_create_user_config {
    allow_admin_create_user_only = true
  }
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }
  tags = {
    Name    = "${var.project_name}-user-pool"
    Project = var.project_name
  }
}

resource "aws_cognito_user_pool_client" "frontend_auth" {
  name         = "${var.project_name}-frontend-client"
  user_pool_id = aws_cognito_user_pool.frontend_auth.id
  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls = [
    "https://${aws_cloudfront_distribution.frontend_distribution.domain_name}/callback.html"
  ]
  logout_urls = [
    "https://${aws_cloudfront_distribution.frontend_distribution.domain_name}/"
  ]
}

resource "aws_cognito_user_pool_domain" "frontend_auth" {
  domain       = var.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.frontend_auth.id
}
