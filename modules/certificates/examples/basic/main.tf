# Minimal usage example, and the fixture module CI plans offline.
#
# CI plans this with a dummy API token, so it must stay offline-plannable: no
# data sources, and every input a literal. The IDs are placeholders from no real
# account; keep them that way so the example stays customer-agnostic.
#
# No custom certificate and no Origin CA CSR: PEM material, even a dummy, would
# trip the repo's secret scanner, and a fake CSR would only fail at apply.

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

module "certificates" {
  source = "../.."

  zone_id   = "0123456789abcdef0123456789abcdef"
  zone_name = "example.com"

  total_tls = {
    enabled               = true
    certificate_authority = "google"
  }

  # Relative labels and "*" exercise hostname qualification; the apex is added.
  certificate_packs = {
    edge = {
      hosts                 = ["www", "*"]
      certificate_authority = "google"
      validation_method     = "txt"
      validity_days         = 90
    }
  }
}
