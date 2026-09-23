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

module "logpush_job" {
  source = "../.."

  zone_id = "0123456789abcdef0123456789abcdef"
  name    = "example-http-requests"
  dataset = "http_requests"

  # An S3 destination rather than R2, so no credential has to appear in the URI.
  # The challenge is a placeholder; the real one is the file Cloudflare writes
  # into the bucket.
  destination_conf    = "s3://example-logs/http/{DATE}?region=eu-west-2&sse=AES256"
  ownership_challenge = "placeholder-not-a-secret"

  # Formatted over several lines, so the compact re-serialisation is exercised.
  filter = <<-EOT
    {
      "where": {
        "and": [
          { "key": "ClientRequestHost", "operator": "eq", "value": "example.com" }
        ]
      }
    }
  EOT

  max_upload_interval_seconds = 60

  output_options = {
    field_names       = ["ClientIP", "ClientRequestHost", "EdgeResponseStatus", "EdgeStartTimestamp"]
    timestamp_format  = "rfc3339"
    cve_2021_44228    = true
    merge_subrequests = true
  }
}
