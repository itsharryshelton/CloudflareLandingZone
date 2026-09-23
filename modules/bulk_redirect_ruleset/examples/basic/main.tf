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

module "bulk_redirect_ruleset" {
  source = "../.."

  account_id = "0123456789abcdef0123456789abcdef"

  # The lists are referenced by name only, so they need not exist for a plan.
  # One unscoped rule and one scoped, so both expression shapes are built.
  rules = [
    {
      list_name   = "marketing_redirects"
      description = "Retired campaign URLs"
    },
    {
      list_name       = "brand_b_redirects"
      scope_hostnames = ["www.example.net"]
      scope_domains   = ["example.org"]
    },
  ]
}
