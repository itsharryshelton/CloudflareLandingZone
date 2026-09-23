# Minimal usage example, and the fixture module CI plans offline.
#
# CI plans this with a dummy API token, so it must stay offline-plannable: no
# data sources, and every input a literal. The IDs are placeholders from no real
# account; keep them that way so the example stays customer-agnostic.

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

module "zone_rules" {
  source = "../.."

  zone_id   = "0123456789abcdef0123456789abcdef"
  zone_tier = "pro"

  # manage_subscription stays at its default of false: owning the rate plan
  # makes an apply a billing event, which an example should never model.

  # Pro-tier fields only, so the plan gating preconditions pass.
  bot_management = {
    sbfm_definitely_automated = "managed_challenge"
    sbfm_verified_bots        = "allow"
    ai_bots_protection        = "block"
  }
}
