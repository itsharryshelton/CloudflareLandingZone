# Minimal usage example, and the fixture module CI plans offline.
#
# CI plans this with a dummy API token, so it must stay offline-plannable: no
# data sources, and every input a literal. The IDs are placeholders from no real
# account; keep them that way so the example stays customer-agnostic.
#
# When you copy this directory to modules/<name>, keep examples/basic and fill in
# the module block below so the plan creates at least one of each resource the
# module manages. A module with required inputs and no example is not planned.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.7"
    }
  }
}

# Reads CLOUDFLARE_API_TOKEN. An offline plan only creates, so it is never used.
provider "cloudflare" {}

module "template" {
  source = "../.."

  # zone_id    = "0123456789abcdef0123456789abcdef"
  # account_id = "0123456789abcdef0123456789abcdef"
}
