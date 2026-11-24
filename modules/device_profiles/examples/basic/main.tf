# Minimal usage example, and the fixture module CI plans offline.
#
# CI plans this with a dummy API token, so it must stay offline-plannable: no
# data sources, no singletons that would be imported (device settings and the
# default profile are left null here for that reason), and every input a
# literal. Addresses are from RFC 5737 / RFC 6598 documentation and private
# ranges, and names from RFC 2606, so the example stays customer-agnostic.

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

module "device_profiles" {
  source = "../.."

  account_id = "0123456789abcdef0123456789abcdef"

  custom_profiles = {
    # Engineers reach the lab range through the client, everything else as
    # normal. Exclude mode: the entries are what stays OFF the tunnel.
    engineering = {
      name       = "Engineering"
      precedence = 10
      match = {
        user_group_names = ["Engineering"]
        os_names         = ["windows", "mac"]
      }

      service_mode  = { mode = "warp" }
      switch_locked = true

      split_tunnel = {
        mode = "exclude"
        entries = [
          { address = "192.168.0.0/16", description = "Home and office LANs" },
          { host = "printer.example.com", description = "Local print server" },
        ]
      }

      fallback_domains = [
        { suffix = "corp.example.com", dns_servers = ["192.0.2.53"] },
        { suffix = "local" },
      ]
    }

    # Contractors: only the application range goes through the client.
    contractors = {
      name             = "Contractors"
      precedence       = 20
      match_expression = "identity.email matches \".*@contractor\\.example\\.net\""

      split_tunnel = {
        mode = "include"
        entries = [
          { address = "198.51.100.0/24", description = "Application range" },
        ]
      }
    }
  }
}
