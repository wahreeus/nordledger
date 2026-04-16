#!/usr/bin/env bash
set -euo pipefail

TF_DIR="terraform/client-mvp"
FRONTEND_DIR="web/client-mvp"
INDEX_FILE="$FRONTEND_DIR/index.html"
CALLBACK_FILE="$FRONTEND_DIR/callback.html"
AUTH_FILE="$FRONTEND_DIR/auth.js"

if [ ! -d "$TF_DIR" ]; then
  echo "Error: Terraform directory '$TF_DIR' does not exist."
  exit 1
fi

if [ ! -d "$FRONTEND_DIR" ]; then
  echo "Error: frontend directory '$FRONTEND_DIR' does not exist."
  exit 1
fi

if [ ! -f "$INDEX_FILE" ]; then
  echo "Error: index file '$INDEX_FILE' does not exist."
  exit 1
fi

if [ ! -f "$CALLBACK_FILE" ]; then
  echo "Error: callback file '$CALLBACK_FILE' does not exist."
  exit 1
fi

if [ ! -f "$AUTH_FILE" ]; then
  echo "Error: callback file '$AUTH_FILE' does not exist."
  exit 1
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo "Error: terraform is not installed."
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "Error: AWS CLI is not installed."
  exit 1
fi

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "Error: AWS credentials are not configured correctly."
  exit 1
fi

escape_sed() {
  printf '%s' "$1" | sed 's/[&|]/\\&/g'
}

echo "Initializing Terraform in $TF_DIR ..."
terraform -chdir="$TF_DIR" init

echo "Applying Terraform in $TF_DIR ..."
terraform -chdir="$TF_DIR" apply

echo "Reading Terraform outputs..."
AWS_REGION="$(terraform -chdir="$TF_DIR" output -raw aws_region 2>/dev/null || true)"
BUCKET_NAME="$(terraform -chdir="$TF_DIR" output -raw frontend_bucket_name 2>/dev/null || true)"
CF_DIST_ID="$(terraform -chdir="$TF_DIR" output -raw cloudfront_distribution_id 2>/dev/null || true)"
SITE_DOMAIN="$(terraform -chdir="$TF_DIR" output -raw cloudfront_domain_name 2>/dev/null || true)"
SITE_URL="$(terraform -chdir="$TF_DIR" output -raw frontend_url 2>/dev/null || true)"
LOGIN_URL="$(terraform -chdir="$TF_DIR" output -raw cognito_login_url 2>/dev/null || true)"
COGNITO_DOMAIN="$(terraform -chdir="$TF_DIR" output -raw cognito_domain 2>/dev/null || true)"
CLIENT_ID="$(terraform -chdir="$TF_DIR" output -raw cognito_app_client_id 2>/dev/null || true)"
POOL_ID="$(terraform -chdir="$TF_DIR" output -raw cognito_user_pool_id 2>/dev/null || true)"


if [ -z "$BUCKET_NAME" ]; then
  echo "Error: Terraform output 'frontend_bucket_name' was not found."
  exit 1
fi

if [ -z "$SITE_DOMAIN" ]; then
  echo "Error: Terraform output 'cloudfront_domain_name' was not found."
  exit 1
fi

if [ -z "$COGNITO_DOMAIN" ]; then
  echo "Error: Terraform output 'cognito_domain' was not found."
  exit 1
fi

if [ -z "$CLIENT_ID" ]; then
  echo "Error: Terraform output 'cognito_app_client_id' was not found."
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Preparing frontend files in temporary directory..."
cp -R "$FRONTEND_DIR/." "$TMP_DIR/"

echo "Rendering index.html ..."
sed \
  -e "s|REPLACE_WITH_COGNITO_DOMAIN|$(escape_sed "$COGNITO_DOMAIN")|g" \
  -e "s|REPLACE_WITH_APP_CLIENT_ID|$(escape_sed "$CLIENT_ID")|g" \
  -e "s|REPLACE_WITH_SITE_DOMAIN|$(escape_sed "$SITE_DOMAIN")|g" \
  "$INDEX_FILE" > "$TMP_DIR/index.html"

echo "Rendering callback.html ..."
sed \
  -e "s|REPLACE_WITH_COGNITO_DOMAIN|$(escape_sed "$COGNITO_DOMAIN")|g" \
  -e "s|REPLACE_WITH_APP_CLIENT_ID|$(escape_sed "$CLIENT_ID")|g" \
  -e "s|REPLACE_WITH_SITE_DOMAIN|$(escape_sed "$SITE_DOMAIN")|g" \
  "$CALLBACK_FILE" > "$TMP_DIR/callback.html"

echo "Rendering auth.js ..."
sed \
  -e "s|REPLACE_WITH_COGNITO_DOMAIN|$(escape_sed "$COGNITO_DOMAIN")|g" \
  -e "s|REPLACE_WITH_APP_CLIENT_ID|$(escape_sed "$CLIENT_ID")|g" \
  -e "s|REPLACE_WITH_USER_POOL_ID|$(escape_sed "$POOL_ID")|g" \
  -e "s|REPLACE_WITH_AWS_REGION|$(escape_sed "$AWS_REGION")|g" \
  "$AUTH_FILE" > "$TMP_DIR/auth.js"

echo "Uploading frontend files to s3://$BUCKET_NAME ..."
aws s3 sync "$TMP_DIR/" "s3://$BUCKET_NAME/" --delete

if [ -n "$CF_DIST_ID" ]; then
  echo "Creating CloudFront invalidation..."
  aws cloudfront create-invalidation \
    --distribution-id "$CF_DIST_ID" \
    --paths "/*" >/dev/null
  echo "CloudFront invalidation submitted."
fi

echo
echo "Done."
[ -n "$SITE_URL" ] && echo "Frontend URL: $SITE_URL"
[ -n "$LOGIN_URL" ] && echo "Cognito login URL: $LOGIN_URL"