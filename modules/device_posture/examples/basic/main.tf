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

module "device_posture" {
  source = "../.."

  account_id = "0123456789abcdef0123456789abcdef"

  # Kolide needs only a secret, so it is the smallest integration to plan. The
  # value is a placeholder; Cloudflare tests it at apply, never at plan.
  integrations = [
    {
      name     = "Kolide"
      type     = "kolide"
      interval = "1h"
      config = {
        client_secret = "placeholder-not-a-secret"
      }
    },
  ]

  # One client check and one service provider check, so both input paths and
  # the integration_name lookup are exercised.
  rules = [
    {
      name      = "Windows 10 22H2 or later"
      type      = "os_version"
      schedule  = "5m"
      platforms = ["windows"]
      input = {
        operating_system = "windows"
        operator         = ">="
        version          = "10.0.19045"
      }
    },
    {
      name             = "Kolide healthy"
      type             = "kolide"
      expiration       = "2h"
      integration_name = "Kolide"
      input = {
        auth_state = ["Good"]
      }
    },
  ]
}
