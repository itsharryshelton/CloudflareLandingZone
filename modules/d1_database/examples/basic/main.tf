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

module "d1_database" {
  source = "../.."

  account_id = "0123456789abcdef0123456789abcdef"
  name       = "example-app"

  # A hint inside the jurisdiction, so the residency precondition is exercised.
  jurisdiction          = "eu"
  primary_location_hint = "weur"

  # Disabled rather than auto: replicas would copy data out of the jurisdiction.
  read_replication_mode = "disabled"
}
