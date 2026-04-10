############################
# Frontend Outputs
############################

output "frontend_bucket_name" {
  value = aws_s3_bucket.frontend_bucket.bucket
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.frontend_distribution.id
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.frontend_distribution.domain_name
}

output "frontend_url" {
  value = "https://${aws_cloudfront_distribution.frontend_distribution.domain_name}"
}

output "frontend_base_url" {
  value = "https://${aws_cloudfront_distribution.frontend_distribution.domain_name}"
}

############################
# Authentication Outputs
############################

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.frontend_auth.id
}

output "cognito_app_client_id" {
  value = aws_cognito_user_pool_client.frontend_auth.id
}

output "cognito_domain" {
  value = "${aws_cognito_user_pool_domain.frontend_auth.domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
}

output "cognito_login_url" {
  value = "https://${aws_cognito_user_pool_domain.frontend_auth.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/oauth2/authorize?response_type=code&client_id=${aws_cognito_user_pool_client.frontend_auth.id}&redirect_uri=https://${aws_cloudfront_distribution.frontend_distribution.domain_name}/callback.html&scope=openid+email+profile"
}