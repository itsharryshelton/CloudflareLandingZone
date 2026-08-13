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
  # One state per account per layer. Pass the varying parts at init time so
  # nothing account-specific is committed:
  #
  #   terraform init -reconfigure \
  #     -backend-config="bucket=<state-bucket>" \
  #     -backend-config="key=<account_key>/gateway.tfstate" \
  #     -backend-config="endpoints={s3=\"https://<state-account-id>.r2.cloudflarestorage.com\"}"
  #
  # Credentials come from the environment, NEVER from this file:
  #   AWS_ACCESS_KEY_ID     = R2 access key id
  #   AWS_SECRET_ACCESS_KEY = R2 secret access key
  # Use a bucket-scoped R2 API token with Object Read & Write only.
  #
  # LOCKING: R2 has no DynamoDB equivalent, so two concurrent applies against one
  # state key can corrupt it. `use_lockfile = true` locks using S3 conditional
  # writes, which R2 supports. That is the protection, and it is why
  # required_version above is 1.11 rather than 1.5: on an older Terraform the
  # argument is not understood, and the failure mode is an unlocked apply rather
  # than an error.
  #
  # The pipeline additionally serialises runs per state key with a concurrency
  # group, as a second line of defence. See .github/workflows/_terraform-run.yml.
  #
  # This layer's state holds no credentials, but it does hold the complete egress
  # filtering posture of the estate: every category and application that is
  # inspected or bypassed, every DLP profile in force, and every internal range
  # named in a source or destination selector. Read as a whole it is a map of
  # what is watched and what is not, which is exactly what somebody planning to
  # move data out would want. Keep the bucket private and treat a saved plan file
  # the same way.
  #
  # Left commented so CI can run `terraform init -backend=false` with no R2
  # dependency. Uncomment for any real deployment.
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
