terraform {
  required_version = ">= 1.11.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.7"
    }
  }

  # ---------------------------------------------------------------------------
  # Remote state: Cloudflare R2 via the S3-compatible backend
  # ---------------------------------------------------------------------------
  # https://developers.cloudflare.com/terraform/advanced-topics/remote-backend/
  #
  # One state per account per layer:
  #
  #   terraform init -reconfigure \
  #     -backend-config="bucket=<state-bucket>" \
  #     -backend-config="key=<account_key>/waf.tfstate" \
  #     -backend-config="endpoints={s3=\"https://<state-account-id>.r2.cloudflarestorage.com\"}"
  #
  # Credentials come from the environment, NEVER from this file:
  #   AWS_ACCESS_KEY_ID     = R2 access key id
  #   AWS_SECRET_ACCESS_KEY = R2 secret access key
  # Use a bucket-scoped R2 API token with Object Read & Write only.
  #
  # LOCKING: R2 has no DynamoDB equivalent, so two concurrent applies against one
  # state key can corrupt it. `use_lockfile = true` locks using S3 conditional
  # writes, which R2 supports, and is why required_version above is 1.11. The
  # pipeline also serialises per state key. See ../zones/terraform.tf for the full
  # reasoning.
  #
  # backend "s3" {
  #   region                      = "auto"
  #   use_path_style              = true
  #   use_lockfile                = true
  #   skip_credentials_validation = true
  #   skip_metadata_api_check     = true
  #   skip_region_validation      = true
  #   skip_requesting_account_id  = true
  #   skip_s3_checksum            = true
  # }
}
