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

module "bulk_redirect_list" {
  source = "../.."

  account_id  = "0123456789abcdef0123456789abcdef"
  name        = "legacy_domain_redirects"
  description = "Retired marketing paths redirected to their replacements."

  # Managed rows, so the item reshaping and source-URL checks are exercised.
  manage_items = true
  items = [
    {
      source_url  = "www.example.net/old-page"
      target_url  = "https://www.example.com/new-page"
      status_code = 301
    },
    {
      source_url           = "example.org/docs"
      target_url           = "https://www.example.com/docs"
      status_code          = 302
      subpath_matching     = true
      preserve_path_suffix = true
    },
  ]
}
