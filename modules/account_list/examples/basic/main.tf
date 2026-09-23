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

module "account_list" {
  source = "../.."

  account_id  = "0123456789abcdef0123456789abcdef"
  name        = "corporate_egress"
  kind        = "ip"
  description = "Corporate egress ranges, referenced as $corporate_egress."

  # Managed rows, so the kind-mismatch and duplicate-row preconditions run.
  manage_items = true
  items = [
    {
      ip      = "192.0.2.0/24"
      comment = "Primary office egress."
    },
    {
      ip      = "198.51.100.10"
      comment = "Backup VPN concentrator."
    },
  ]
}
