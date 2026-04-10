#!/usr/bin/env bash
set -euo pipefail

TF_DIR="terraform/client-mvp"
BUCKET_NAME="nordledger-frontend"

if [ ! -d "$TF_DIR" ]; then
  echo "Error: Terraform directory '$TF_DIR' does not exist."
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

echo "Initializing Terraform in $TF_DIR ..."
terraform -chdir="$TF_DIR" init

echo "Deleting website files from s3://$BUCKET_NAME ..."
aws s3 rm "s3://$BUCKET_NAME" --recursive || true

echo "Destroying Terraform-managed infrastructure in $TF_DIR ..."
terraform -chdir="$TF_DIR" destroy

echo
echo "Done."