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

module "load_balancer" {
  source = "../.."

  account_id  = "0123456789abcdef0123456789abcdef"
  zone_id     = "0123456789abcdef0123456789abcdee"
  lb_hostname = "app.example.com"

  # Two origins, one with a Host override, so the header mapping and the
  # minimum_origins precondition are exercised.
  origins = [
    {
      name    = "origin-a"
      address = "192.0.2.10"
      weight  = 0.5
    },
    {
      name        = "origin-b"
      address     = "198.51.100.10"
      weight      = 0.5
      port        = 8443
      header_host = ["origin.example.com"]
    },
  ]

  pool_minimum_origins    = 1
  pool_notification_email = "ops@example.com"
  steering_policy         = "random"
}
