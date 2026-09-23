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

module "tunnel" {
  source = "../.."

  account_id = "0123456789abcdef0123456789abcdef"

  # A remotely managed tunnel with a zone_id on its rule, so the config and the
  # public hostname's CNAME are planned alongside the tunnel itself.
  tunnels = [
    {
      name = "Example site"
      ingress = [
        {
          hostname = "app.example.com"
          service  = "http://localhost:8080"
          zone_id  = "0123456789abcdef0123456789abcdee"
        },
      ]
    },
  ]

  virtual_networks = [
    {
      name    = "example-site"
      comment = "Overlapping address space for the example site."
    },
  ]

  # Scoped to the declared virtual network, so the name lookup is exercised.
  routes = [
    {
      network              = "192.0.2.0/24"
      tunnel_name          = "Example site"
      virtual_network_name = "example-site"
      comment              = "Example site private range."
    },
  ]
}
