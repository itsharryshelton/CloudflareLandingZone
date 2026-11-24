terraform {
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
  # One state per account per layer:
  #
  #   terraform init -reconfigure \
  #     -backend-config="bucket=<state-bucket>" \
  #     -backend-config="key=<account_key>/notifications.tfstate" \
  #     -backend-config="endpoints={s3=\"https://<state-account-id>.r2.cloudflarestorage.com\"}"
  #
  # Credentials come from the environment, NEVER from this file:
  #   AWS_ACCESS_KEY_ID     = R2 access key id
  #   AWS_SECRET_ACCESS_KEY = R2 secret access key
  # Use a bucket-scoped R2 API token with Object Read & Write only.
  #
  # LOCKING: R2 has no DynamoDB equivalent, so two concurrent applies against one
  # state key can corrupt it. `use_lockfile = true` locks using S3 conditional
  # writes, which R2 supports, and needs Terraform 1.11 or newer. The pipeline
  # also serialises per state key. See ../zones/terraform.tf for the full
  # reasoning, including why required_version is 1.12.
  #
  # THIS LAYER'S STATE HOLDS EVERY WEBHOOK URL AND cf-webhook-auth SECRET in
  # plain text, because Terraform records what it sent. A Slack, Discord, Google
  # Chat or Feishu webhook URL is itself the credential: anyone holding it can
  # post into that channel as if they were Cloudflare. It also holds every alert
  # recipient's email address. Treat a leak of this state, or of a saved plan of
  # this layer, as a leak of each of those credentials, and rotate them at the
  # chat service.
  #
  # Losing this state is the other failure mode worth naming. A rebuilt state
  # creates a second copy of every policy and destination alongside the ones
  # already at Cloudflare, so every alert arrives twice. Adopt the existing ones
  # instead - see imports.tf.
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
