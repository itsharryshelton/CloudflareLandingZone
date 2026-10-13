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

module "redirect_rules" {
  source = "../.."

  zone_id = "0123456789abcdef0123456789abcdef"

  # One dynamic and one static target, so both branches of the target
  # validation are exercised.
  rules = [
    {
      # The request's query string comes first and the fixed parameter is
      # appended, so a deep link's parameters survive the redirect.
      name                  = "Deep link to the booking app (de)"
      expression            = "http.host eq \"www.example.com\" and (http.request.uri.path eq \"/de/book\" or starts_with(http.request.uri.path, \"/de/book/\"))"
      target_url_expression = "concat(\"https://book.example.com/?\", http.request.uri.query, \"&lang=de\")"
    },
    {
      name                  = "Retired help centre"
      expression            = "http.host eq \"help.example.com\""
      description           = "Help moved to the docs site; keep inbound query parameters."
      target_url            = "https://docs.example.com/support"
      status_code           = 301
      preserve_query_string = true
    },
  ]
}
