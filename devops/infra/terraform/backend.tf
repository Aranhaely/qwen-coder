# =============================================================================
# Remote state backend: S3 bucket + DynamoDB lock table.
# Bootstrap once (see scripts/bootstrap-backend.sh), then uncomment `backend`.
# =============================================================================

# NOTE: the `backend "s3"` block below is intentionally left commented out.
# Terraform does not allow variables inside a backend block; CI passes real
# values via `-backend-config` (see ci/github-actions.yml, job "infra-plan").
# Run scripts/bootstrap-backend.sh once to create the bucket + lock table,
# then uncomment and supply values through a partially-configured backend or
# fully via CLI flags:
#
#   terraform init \
#     -backend-config="bucket=$STATE_BUCKET" \
#     -backend-config="dynamodb_table=$STATE_LOCK_TABLE" \
#     -backend-config="region=us-east-1" \
#     -backend-config="key=env/prod.tfstate" \
#     -backend-config="encrypt=true"

terraform {
  backend "s3" {
    # Intentionally minimal: everything comes from -backend-config in CI.
    # Keep this block so `terraform init` knows the backend type.
  }
}
