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
  #     -backend-config="key=<account_key>/turnstile.tfstate" \
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
  # THIS LAYER'S STATE HOLDS EVERY WIDGET'S SECRET KEY in plain text, because
  # Terraform records what the API returned. That key is the whole of the
  # server-side half of Turnstile: anyone holding it can forge a passing
  # /siteverify response for any form the widget protects. It cannot be rotated
  # in place either - a new secret means a new widget, and a new widget means a
  # new sitekey and a redeploy of every page embedding it. Treat a leak of this
  # state, or of a saved plan of this layer, accordingly.
  #
  # Losing this state is the other failure mode worth naming. A rebuilt state
  # creates fresh widgets with fresh sitekeys while the live pages still carry
  # the old ones, which fails every challenge on every protected form at once.
  # Adopt the existing widgets instead - see imports.tf.
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
