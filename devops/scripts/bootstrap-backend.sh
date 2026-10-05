#!/usr/bin/env bash
# =============================================================================
# One-time bootstrap of the Terraform remote state backend (S3 + DynamoDB).
# Run BEFORE first `terraform init` with -backend-config. Idempotent.
# Requires: aws CLI v2 configured with admin creds for this step only.
# =============================================================================
set -euo pipefail

STATE_BUCKET="${STATE_BUCKET:-myapp-terraform-state}"
LOCK_TABLE="${LOCK_TABLE:-myapp-terraform-lock}"
REGION="${AWS_REGION:-eu-central-1}"

echo "==> Creating S3 bucket '$STATE_BUCKET' in $REGION"
aws s3api create-bucket \
  --bucket "$STATE_BUCKET" \
  --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION" || true

echo "==> Versioning + encryption + public access block"
aws s3api put-bucket-versioning --bucket "$STATE_BUCKET" \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$STATE_BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms"}}]}'
aws s3api put-public-access-block --bucket "$STATE_BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "==> DynamoDB lock table (with 'LockID' key)"
aws dynamodb create-table \
  --table-name "$LOCK_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION" || true

echo "==> Done. Now run:"
echo "  terraform init \\"
echo "    -backend-config=\"bucket=$STATE_BUCKET\" \\"
echo "    -backend-config=\"dynamodb_table=$LOCK_TABLE\" \\"
echo "    -backend-config=\"region=$REGION\""
