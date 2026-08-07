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
  #     -backend-config="key=<account_key>/wan.tfstate" \
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
  # THIS LAYER'S STATE HOLDS LIVE CREDENTIALS. Every IPsec pre-shared key supplied
  # through wan_ipsec_tunnel_psks is in it in plain text, because Cloudflare stores
  # the key and Terraform records what it sent. Marking the variable sensitive
  # keeps the value out of console output and out of the plan comment on a pull
  # request; it does not encrypt state.
  #
  # Treat a leak of this state as a network compromise rather than a configuration
  # disclosure. A PSK plus the two endpoint addresses - both also in here - is
  # everything needed to stand up the customer end of a tunnel into the estate.
  # Rotate every PSK it contains, at both ends. Keep the R2 bucket private, keep
  # its keys in GitHub Environments, and remember that a saved plan file is
  # exactly as sensitive.
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
