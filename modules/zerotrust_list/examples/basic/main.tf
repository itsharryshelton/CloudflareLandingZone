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

# A hostname list, read by a Gateway Domain or Host selector.
module "blocked_domains" {
  source = "../.."

  account_id  = "0123456789abcdef0123456789abcdef"
  name        = "Blocked domains"
  type        = "DOMAIN"
  description = "Domains this account refuses to resolve, beyond the security categories"

  items = [
    { value = "example.net", description = "Placeholder" },
    { value = "example.org" },
  ]
}

# An address list, read by a destination or source IP selector.
module "corporate_egress" {
  source = "../.."

  account_id = "0123456789abcdef0123456789abcdef"
  name       = "Corporate egress ranges"
  type       = "IP"

  items = [
    { value = "192.0.2.0/24", description = "Head office" },
    { value = "198.51.100.10", description = "Data centre NAT" },
  ]
}

output "blocked_domains_reference" {
  description = "How a Gateway expression refers to the hostname list."
  value       = module.blocked_domains.reference
}

output "corporate_egress_id" {
  description = "UUID of the address list."
  value       = module.corporate_egress.id
}
