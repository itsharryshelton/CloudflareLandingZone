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

module "queue_consumer" {
  source = "../.."

  account_id = "0123456789abcdef0123456789abcdef"

  # Literals here; a layer passes module.queues[<key>].queue_id and
  # module.worker_scripts[<key>].script_name, which is what orders the consumer
  # behind both.
  queue_id   = "fedcba9876543210fedcba9876543210"
  queue_name = "example-jobs"

  type              = "worker"
  script_name       = "example-consumer"
  dead_letter_queue = "example-jobs-dlq"

  settings = {
    batch_size  = 10
    max_retries = 3
    retry_delay = 30
  }
}
