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

module "worker_script" {
  source = "../.."

  account_id  = "0123456789abcdef0123456789abcdef"
  script_name = "example-worker-dev"

  # A file rather than inline source, so the content_file/content_sha256 pairing
  # the module insists on is exercised.
  content_file   = "${path.module}/worker.js"
  content_sha256 = filesha256("${path.module}/worker.js")

  compatibility_date = "2025-09-01"

  bindings = [
    {
      name         = "REDIRECTS"
      type         = "kv_namespace"
      namespace_id = "0123456789abcdef0123456789abcde1"
    },
    {
      name = "ENVIRONMENT"
      type = "plain_text"
      text = "dev"
    },
  ]

  # One of each trigger type, so the route, custom domain and cron resources are
  # all planned. Distinct hosts, as the module rejects a route and a custom domain
  # claiming the same one.
  routes = [
    {
      pattern = "www.example.com/*"
      zone_id = "0123456789abcdef0123456789abcde2"
    },
  ]

  custom_domains = [
    {
      hostname = "api.example.com"
      zone_id  = "0123456789abcdef0123456789abcde2"
    },
  ]

  cron_schedules = ["*/30 * * * *"]
}
