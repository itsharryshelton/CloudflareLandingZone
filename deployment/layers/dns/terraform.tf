terraform {
  # 1.12 is the floor. State locking on R2 depends on `use_lockfile`, added in
  # 1.11 (see the LOCKING note below), and the modules this layer calls rely on
  # `||` and `&&` short-circuiting, which Terraform only does from 1.12. Below
  # that, module validations fail on the null inputs they were written to skip.
  required_version = ">= 1.12.0"

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
  #     -backend-config="key=<account_key>/dns.tfstate" \
  #     -backend-config="endpoints={s3=\"https://<state-account-id>.r2.cloudflarestorage.com\"}"
  #
  # Credentials come from the environment, NEVER from this file:
  #   AWS_ACCESS_KEY_ID     = R2 access key id
  #   AWS_SECRET_ACCESS_KEY = R2 secret access key
  # Use a bucket-scoped R2 API token with Object Read & Write only.
  #
  # LOCKING: R2 has no DynamoDB equivalent, so two concurrent applies against one
  # state key can corrupt it. `use_lockfile = true` locks using S3 conditional
  # writes, which R2 supports. That is the protection, and it needs Terraform
  # 1.11 or newer: on an older Terraform the argument is not understood, and the
  # failure mode is an unlocked apply rather than an error.
  #
  # The pipeline additionally serialises runs per state key with a concurrency
  # group, as a second line of defence. See .github/workflows/_terraform-run.yml.
  #
  # Left commented so CI can run `terraform init -backend=false` with no R2
  # dependency. Uncomment for any real deployment - state holds zone IDs, DNS
  # record contents and full WAF rule expressions.
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
