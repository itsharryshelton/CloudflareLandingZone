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

module "wan" {
  source = "../.."

  account_id = "0123456789abcdef0123456789abcdef"

  # One tunnel of each type. psk is left unset so Cloudflare generates it, which
  # keeps a credential out of the example and out of state.
  ipsec_tunnels = [
    {
      name                = "site-ipsec-01"
      description         = "Example site, primary circuit"
      cloudflare_endpoint = "192.0.2.10"
      customer_endpoint   = "203.0.113.10"
      interface_address   = "10.252.0.0/31"

      # Every health_check field is set, so each of its validations is exercised.
      health_check = {
        enabled   = true
        direction = "bidirectional"
        rate      = "mid"
        type      = "reply"
      }
    },
  ]

  gre_tunnels = [
    {
      name                = "site-gre-01"
      description         = "Example site, secondary circuit"
      cloudflare_endpoint = "192.0.2.10"
      customer_endpoint   = "203.0.113.11"
      interface_address   = "10.252.0.2/31"

      health_check = {
        enabled   = true
        direction = "unidirectional"
        rate      = "mid"
        type      = "request"
        target    = "10.10.0.1"
      }
    },
  ]

  # One prefix down both tunnels, active/standby. tunnel_name rather than nexthop
  # exercises the module's derivation of the customer side of each /31.
  static_routes = [
    {
      prefix      = "10.10.0.0/16"
      tunnel_name = "site-ipsec-01"
      priority    = 100
      description = "Example site LAN, preferred path"
    },
    {
      prefix      = "10.10.0.0/16"
      tunnel_name = "site-gre-01"
      priority    = 200
      description = "Example site LAN, standby path"
    },
  ]
}
