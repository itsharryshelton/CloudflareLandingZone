terraform {
  required_version = ">= 1.12.0"

  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
      # Not the ~> 5.7 the other layers carry: the AI Gateway resources first
      # shipped in 5.19.0, and guardrails and spend_limits in 5.20.0. The module
      # sets the same floor; stating it here too keeps the lock file's recorded
      # constraint honest.
      version = "~> 5.20"
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
  #     -backend-config="key=<account_key>/ai_gateway.tfstate" \
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
  # This layer's state holds no credential. It carries gateway settings, DLP
  # profile IDs and the Logpush public key, and nothing that lets anyone call a
  # gateway - that takes a Cloudflare token with AI Gateway Run, which this
  # layer neither creates nor reads. The logs are a different matter: they hold
  # prompts and responses, and live at Cloudflare, not here. See providers.tf.
  #
  # Losing this state is recoverable but not free. A rebuilt state tries to
  # create gateways whose IDs already exist, and the API refuses them, after
  # the plan was approved. Adopt them instead - see imports.tf.
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
