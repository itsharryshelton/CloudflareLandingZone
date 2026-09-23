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

module "r2_bucket" {
  source = "../.."

  account_id = "0123456789abcdef0123456789abcdef"
  name       = "example-assets"
  location   = "weur"

  # One entry per optional list, so every configuration resource is planned.
  cors_rules = [
    {
      id              = "site-reads"
      allowed_origins = ["https://www.example.com"]
      allowed_methods = ["GET", "HEAD"]
      max_age_seconds = 3600
    },
  ]

  lifecycle_rules = [
    {
      id                                 = "abort-stale-uploads"
      abort_multipart_uploads_after_days = 7
    },
    {
      id                        = "expire-tmp"
      prefix                    = "tmp/"
      delete_objects_after_days = 30
    },
  ]

  # Prefix kept apart from expire-tmp, which the overlap precondition requires.
  lock_rules = [
    {
      id              = "retain-audit"
      prefix          = "audit/"
      retain_for_days = 365
    },
  ]

  custom_domains = [
    {
      domain  = "assets.example.com"
      zone_id = "0123456789abcdef0123456789abcde1"
    },
  ]
}
