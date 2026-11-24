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

# An office whose router forwards DNS to the Gateway IPv4 resolvers, plus a
# DoH endpoint that demands an identity token so it can be used off-site.
module "dns_location" {
  source = "../.."

  account_id = "0123456789abcdef0123456789abcdef"
  name       = "Head office"

  networks = ["203.0.113.0/24"]

  endpoints = {
    ipv4 = { enabled = true }
    doh  = { enabled = true, require_token = true }
  }
}

output "ipv4_destination" {
  description = "Resolver address the office router points at."
  value       = module.dns_location.ipv4_destination
}

output "doh_url" {
  description = "DoH URL for the location."
  value       = module.dns_location.doh_url
}
