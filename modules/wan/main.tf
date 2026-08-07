# Cloudflare WAN (formerly Magic WAN)
#
# Three things this module deliberately does not do.
#
# It does not enable Cloudflare WAN. That is an Enterprise entitlement.
# It does not touch Magic Transit or Magic Firewall.
# It does not manage the device at the other end.
#
# Normalisation lives in locals.tf. 

resource "cloudflare_magic_wan_gre_tunnel" "this" {
  for_each = local.gre_tunnels

  account_id = var.account_id

  name                    = each.value.name
  description             = each.value.description
  cloudflare_gre_endpoint = each.value.cloudflare_endpoint
  customer_gre_endpoint   = each.value.customer_endpoint
  interface_address       = each.value.interface_address
  interface_address6      = each.value.interface_address6

  mtu                      = each.value.mtu
  ttl                      = each.value.ttl
  automatic_return_routing = each.value.automatic_return_routing

  health_check = local.gre_health_checks[each.key]
  bgp          = local.gre_bgp[each.key]

  lifecycle {
    precondition {
      condition     = length(local.duplicate_tunnel_names) == 0
      error_message = "Two tunnels share a name: ${join(", ", local.duplicate_tunnel_names)}. GRE and IPsec tunnels share one name space on a Cloudflare account, and the name is the tunnel's identity, so the second would fight over the first."
    }

    precondition {
      condition     = length(local.overlapping_interface_addresses) == 0
      error_message = "Two tunnels are numbered from the same /31: ${join("; ", local.overlapping_interface_addresses)}. Cloudflare accepts both and the two then claim the same next hop, so a static route reaches whichever the edge picks."
    }

    precondition {
      condition     = length(local.health_checks_with_ignored_targets) == 0
      error_message = "These tunnels set a bidirectional health check and a target: ${join(", ", local.health_checks_with_ignored_targets)}. A bidirectional check probes through the tunnel and back, and uses the interface address as its target, so the value given is discarded - which reads as a health check aimed at something it is not. Drop the target, or use direction = \"unidirectional\"."
    }
  }
}

# The PSK reaches Terraform state in plain text whatever route it takes here,
# because Cloudflare stores it and Terraform records what it sent. Left unset,
# Cloudflare generates one that is never returned, so the only copy is in the
# dashboard.
resource "cloudflare_magic_wan_ipsec_tunnel" "this" {
  for_each = local.ipsec_tunnels

  account_id = var.account_id

  name                = each.value.name
  description         = each.value.description
  cloudflare_endpoint = each.value.cloudflare_endpoint
  customer_endpoint   = each.value.customer_endpoint
  interface_address   = each.value.interface_address
  interface_address6  = each.value.interface_address6

  psk                      = each.value.psk
  replay_protection        = each.value.replay_protection
  automatic_return_routing = each.value.automatic_return_routing

  custom_remote_identities = local.ipsec_custom_remote_identities[each.key]

  health_check = local.ipsec_health_checks[each.key]
  bgp          = local.ipsec_bgp[each.key]

  # Repeated from the GRE resource rather than shared: a deployment with only
  # IPsec tunnels has no GRE instances for a precondition to be evaluated on.
  lifecycle {
    precondition {
      condition     = length(local.duplicate_tunnel_names) == 0
      error_message = "Two tunnels share a name: ${join(", ", local.duplicate_tunnel_names)}. GRE and IPsec tunnels share one name space on a Cloudflare account, and the name is the tunnel's identity, so the second would fight over the first."
    }

    precondition {
      condition     = length(local.overlapping_interface_addresses) == 0
      error_message = "Two tunnels are numbered from the same /31: ${join("; ", local.overlapping_interface_addresses)}. Cloudflare accepts both and the two then claim the same next hop, so a static route reaches whichever the edge picks."
    }

    precondition {
      condition     = length(local.health_checks_with_ignored_targets) == 0
      error_message = "These tunnels set a bidirectional health check and a target: ${join(", ", local.health_checks_with_ignored_targets)}. A bidirectional check probes through the tunnel and back, and uses the interface address as its target, so the value given is discarded - which reads as a health check aimed at something it is not. Drop the target, or use direction = \"unidirectional\"."
    }
  }
}

# The Magic routing table. A tunnel with no route pointing down it carries
# nothing, and a route pointing at the wrong end of a /31 is a blackhole that
# looks healthy.
resource "cloudflare_magic_wan_static_route" "this" {
  for_each = local.static_routes

  account_id = var.account_id

  prefix      = each.value.prefix
  nexthop     = each.value.nexthop
  priority    = each.value.priority
  weight      = each.value.weight
  description = each.value.description
  scope       = each.value.scope

  lifecycle {
    precondition {
      condition     = length(local.routes_naming_unknown_tunnels) == 0
      error_message = "These static routes name a tunnel this module does not declare: ${join("; ", local.routes_naming_unknown_tunnels)}. Declared tunnels: ${join(", ", sort(local.tunnel_names))}. Use nexthop for a tunnel managed elsewhere."
    }

    precondition {
      condition     = length(local.ipv6_routes_over_ipv4_only_tunnels) == 0
      error_message = "These static routes carry an IPv6 prefix over a tunnel with no IPv6 addressing: ${join("; ", local.ipv6_routes_over_ipv4_only_tunnels)}. Give the tunnel an interface_address6, or point the route at an explicit nexthop."
    }

    precondition {
      condition     = length(local.routes_to_cloudflare_side) == 0
      error_message = "These static routes point at Cloudflare's own end of a tunnel's /31 rather than the customer device's: ${join("; ", local.routes_to_cloudflare_side)}. Cloudflare accepts the route and shows it as configured, and the traffic goes nowhere. Use tunnel_name and let the module work the address out."
    }

    precondition {
      condition     = length(local.duplicate_static_routes) == 0
      error_message = "These prefix and next hop pairs are declared more than once: ${join("; ", local.duplicate_static_routes)}. Two routes for one prefix belong down two different tunnels - that is what makes a site survive one failing - so a repeat is a copied line with the next hop left unchanged."
    }
  }
}
