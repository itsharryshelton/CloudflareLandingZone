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
      version = "~> 5.20"
    }
  }
}

# Reads CLOUDFLARE_API_TOKEN. An offline plan only creates, so it is never used.
provider "cloudflare" {}

module "ai_gateway" {
  source = "../.."

  account_id = "0123456789abcdef0123456789abcdef"
  gateway_id = "example-assistant"

  cache      = { ttl = 300 }
  rate_limit = { limit = 600, interval = 60, technique = "sliding" }
  retries    = { max_attempts = 2, delay_ms = 500, backoff = "exponential" }

  # A placeholder profile UUID, so the DLP policy mapping is planned.
  dlp_policies = {
    block-card-numbers = {
      action   = "BLOCK"
      check    = ["REQUEST", "RESPONSE"]
      profiles = ["00000000-0000-4000-8000-000000000000"]
    }
  }

  guardrails = {
    prompt   = { prompt_injection = "BLOCK", hate = "FLAG" }
    response = { hate = "FLAG" }
  }

  # A metadata partition and a filter, so both metadata modes are planned.
  spend_limits = {
    per_user = {
      limit        = 5
      window       = 86400
      partition_by = ["user_id"]
    }
    premium_models = {
      limit            = 200
      window           = 86400
      technique        = "fixed"
      providers        = ["openai"]
      metadata_filters = { team = ["research"] }
    }
  }

  # Every element type the module supports, so the graph checks and the
  # output and property mapping all have something to walk.
  routes = {
    support-default = {
      elements = {
        start = { type = "start", outputs = { next = "plan_check" } }
        plan_check = {
          type       = "conditional"
          conditions = jsonencode({ "metadata.plan" = { "$eq" = "free" } })
          outputs    = { true = "per_user_cap", false = "primary" }
        }
        per_user_cap = {
          type       = "rate"
          key        = "metadata.user_id"
          limit      = 100
          limit_type = "count"
          window     = 3600
          outputs    = { success = "primary", fallback = "budget" }
        }
        primary = {
          type     = "model"
          provider = "openai"
          model    = "gpt-5-mini"
          retries  = 1
          timeout  = 30000
          outputs  = { success = "end", fallback = "budget" }
        }
        budget = {
          type     = "model"
          provider = "workers-ai"
          model    = "@cf/meta/llama-3.1-8b-instruct"
          retries  = 0
          timeout  = 30000
          outputs  = { success = "end" }
        }
        end = { type = "end" }
      }
    }
  }
}
