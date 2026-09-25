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

module "waf" {
  source = "../.."

  zone_id = "0123456789abcdef0123456789abcdef"

  # One of each rule family, so every ruleset the module owns is planned.
  custom_block_rules = [
    {
      name        = "Block legacy XML-RPC endpoint"
      expression  = "http.request.uri.path eq \"/xmlrpc.php\""
      description = "Unused by this application and heavily probed."
    },
  ]

  rate_limiting_rules = [
    {
      name       = "Login brute force"
      expression = "http.request.uri.path eq \"/login\""
      period     = 60
      requests   = 10
    },
  ]

  bot_traffic = {
    search   = "allow"
    agent    = "managed_challenge"
    training = "block"
  }

  # The ruleset ID is a global constant, not account-specific. The rule ID is a
  # placeholder: take the real one from the Security Events entry of the block.
  managed_rulesets = [
    {
      id          = "efb7b8c949ac4650a09736fc376e9aee"
      description = "Cloudflare Managed Ruleset"
    },
  ]

  managed_exceptions = [
    {
      name       = "Template API accepts HTML by design"
      expression = "http.host eq \"app.example.com\" and http.request.method eq \"POST\" and starts_with(http.request.uri.path, \"/templates/\")"
      logging    = true
      skip = {
        rules = {
          "efb7b8c949ac4650a09736fc376e9aee" = ["0123456789abcdef0123456789abcdef"]
        }
      }
    },
  ]
}
