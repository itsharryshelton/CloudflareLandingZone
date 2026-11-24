# Minimal usage example, and the fixture module CI plans offline.
#
# CI plans this with a dummy API token, so it must stay offline-plannable: no
# data sources, and every input a literal. The IDs and URLs are placeholders
# from no real account; keep them that way so the example stays
# customer-agnostic. A real webhook URL or secret never goes in a file - the
# calling layer supplies both from a sensitive TF_VAR_.

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

module "notifications" {
  source = "../.."

  account_id = "0123456789abcdef0123456789abcdef"

  webhooks = {
    ops_receiver = { name = "Example ops receiver" }
  }

  webhook_urls = {
    ops_receiver = "https://alerts.example.com/cloudflare"
  }

  webhook_secrets = {
    ops_receiver = "placeholder-not-a-real-secret"
  }

  policies = {
    # Account-wide, email only.
    incidents = {
      name             = "Cloudflare incidents"
      alert_type       = "incident_alert"
      email_recipients = ["noc@example.com"]
      filters = {
        incident_impact = ["INCIDENT_IMPACT_MAJOR", "INCIDENT_IMPACT_CRITICAL"]
      }
    }

    # Scoped to one zone by ID, sent to the webhook declared above.
    origin_errors = {
      name           = "Origin error rate (example.com)"
      alert_type     = "http_alert_origin_error"
      alert_interval = "1h"
      email_recipients = [
        "noc@example.com",
      ]
      webhook_keys = ["ops_receiver"]
      filters = {
        zones = ["fedcba9876543210fedcba9876543210"]
      }
    }
  }
}
