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

module "queue" {
  source = "../.."

  account_id = "0123456789abcdef0123456789abcdef"
  queue_name = "example-jobs"

  settings = {
    message_retention_period = 345600
  }

  # A push consumer, so the consumer resource and its preconditions are planned.
  # The Worker is named literally here; a layer passes the deployed Worker's name.
  consumer = {
    type              = "worker"
    script_name       = "example-consumer"
    dead_letter_queue = "example-jobs-dlq"
    settings = {
      batch_size  = 10
      max_retries = 3
      retry_delay = 30
    }
  }
}
