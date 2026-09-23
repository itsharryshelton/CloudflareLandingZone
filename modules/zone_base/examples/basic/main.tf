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

module "zone_base" {
  source = "../.."

  account_id  = "0123456789abcdef0123456789abcdef"
  domain_name = "example.com"

  # Merged over the module's secure baseline rather than replacing it.
  zone_settings = {
    brotli = "on"
  }

  # "@", a relative label and an MX, so the name qualification and the priority
  # rule are both exercised.
  dns_records = [
    {
      name    = "@"
      type    = "A"
      content = "192.0.2.10"
      proxied = true
    },
    {
      name    = "www"
      type    = "CNAME"
      content = "example.com"
      proxied = true
    },
    {
      name     = "@"
      type     = "MX"
      content  = "mail.example.net"
      priority = 10
      ttl      = 3600
    },
  ]
}
