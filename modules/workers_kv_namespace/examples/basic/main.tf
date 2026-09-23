# Minimal usage example, and the fixture module CI plans offline.
#
# CI plans this with a dummy API token, so it must stay offline-plannable: no
# data sources, and every input a literal. The IDs are placeholders from no real
# account; keep them that way so the example stays customer-agnostic.

terraform {
  required_version = ">= 1.12.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.7"
    }
  }
}

# Reads CLOUDFLARE_API_TOKEN. An offline plan only creates, so it is never used.
provider "cloudflare" {}

module "workers_kv_namespace" {
  source = "../.."

  account_id = "0123456789abcdef0123456789abcdef"
  title      = "example-config"

  # A pair with metadata, so the key resource and the metadata JSON check are
  # both exercised.
  pairs = {
    "maintenance-mode" = {
      value    = "false"
      metadata = "{\"owner\":\"ops@example.com\"}"
    }
  }
}
