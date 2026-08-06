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
  #     -backend-config="key=<account_key>/zerotrust.tfstate" \
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
  # THIS LAYER'S STATE HOLDS LIVE CREDENTIALS. Every service token's client
  # secret is in it in plain text, because Cloudflare shows a generated secret
  # once and Terraform records what it received. So is every identity provider's
  # OAuth client secret, including the Entra ID one, because Terraform records
  # what it sent. Marking them sensitive hides them from console output and from
  # the plan comment; it does not encrypt state.
  #
  # Treat a leak of this state as a credential compromise, not a configuration
  # disclosure: rotate every service token and every identity provider secret it
  # contains. Keep the R2 bucket private, keep its keys in GitHub Environments,
  # and remember that a saved plan file is exactly as sensitive.
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
