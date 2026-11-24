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

module "dlp_profile" {
  source = "../.."

  account_id  = "0123456789abcdef0123456789abcdef"
  name        = "Internal identifiers"
  description = "Project codes and staff numbers that should not leave the organisation"

  # One stray match is noise; a bulk export is the thing worth blocking.
  allowed_match_count = 5

  entries = [
    {
      name        = "Project code"
      regex       = "PRJ-[0-9]{6}"
      description = "Internal project reference"
    },
    {
      name  = "Staff number"
      regex = "\\bEMP[0-9]{7}\\b"
    },
  ]
}

output "dlp_profile_id" {
  description = "UUID a Gateway HTTP policy names to block on this profile."
  value       = module.dlp_profile.id
}
