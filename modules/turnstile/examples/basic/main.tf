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

module "turnstile" {
  source = "../.."

  account_id = "0123456789abcdef0123456789abcdef"

  widgets = {
    login = {
      name    = "Example login form"
      domains = ["example.com"]
      mode    = "managed"
    }
    # A second widget on another hostname, so the cross-widget overlap and
    # duplicate-name preconditions have something to compare.
    contact = {
      name            = "Example contact form"
      domains         = ["example.net"]
      mode            = "non-interactive"
      clearance_level = "jschallenge"
    }
  }
}
