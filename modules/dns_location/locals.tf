# Provider-shaped endpoints and the cross-field checks main.tf asserts.

locals {
  # Every endpoint is sent, enabled or not. The provider requires all four once
  # `endpoints` is present, and leaving the block out would let Cloudflare pick
  # what a new location answers on.
  endpoints = {
    ipv4 = {
      enabled = var.endpoints.ipv4.enabled
    }
    ipv6 = {
      enabled  = var.endpoints.ipv6.enabled
      networks = [for cidr in var.endpoints.ipv6.networks : { network = cidr }]
    }
    doh = {
      enabled       = var.endpoints.doh.enabled
      networks      = [for cidr in var.endpoints.doh.networks : { network = cidr }]
      require_token = var.endpoints.doh.require_token
    }
    dot = {
      enabled  = var.endpoints.dot.enabled
      networks = [for cidr in var.endpoints.dot.networks : { network = cidr }]
    }
  }

  enabled_endpoint_count = length([
    for enabled in [
      var.endpoints.ipv4.enabled, var.endpoints.ipv6.enabled,
      var.endpoints.doh.enabled, var.endpoints.dot.enabled,
    ] : enabled if enabled
  ])

  # Shared resolver addresses identify a location by where the query came from.
  # With no source networks and no dedicated pair, nothing ties an IPv4 query to
  # this location.
  ipv4_unattributable = var.endpoints.ipv4.enabled && length(var.networks) == 0 && var.dns_destination_ips_id == null

  unrestricted_endpoints = compact([
    var.endpoints.ipv6.enabled && length(var.endpoints.ipv6.networks) == 0 ? "ipv6" : "",
    var.endpoints.doh.enabled && length(var.endpoints.doh.networks) == 0 && !var.endpoints.doh.require_token ? "doh" : "",
    var.endpoints.dot.enabled && length(var.endpoints.dot.networks) == 0 ? "dot" : "",
  ])
}
