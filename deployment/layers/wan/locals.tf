# Applies the platform baseline, resolves tunnel keys to the tunnel names and
# next-hop addresses the module works in, and derives the preflight assertions,
# so that wan.tf reads as a plain module call.

locals {
  # Key -> Cloudflare name. GRE and IPsec tunnels share one name space on the
  # account, so a static route's tunnel_key resolves against both.
  tunnel_names_by_key = merge(
    { for key, tunnel in var.wan_gre_tunnels : key => tunnel.name },
    { for key, tunnel in var.wan_ipsec_tunnels : key => tunnel.name },
  )

  interface_addresses_by_key = merge(
    { for key, tunnel in var.wan_gre_tunnels : key => tunnel.interface_address },
    { for key, tunnel in var.wan_ipsec_tunnels : key => tunnel.interface_address },
  )

  interface_addresses6_by_key = merge(
    { for key, tunnel in var.wan_gre_tunnels : key => tunnel.interface_address6 if tunnel.interface_address6 != null },
    { for key, tunnel in var.wan_ipsec_tunnels : key => tunnel.interface_address6 if tunnel.interface_address6 != null },
  )

  # The customer end of each tunnel's /31. The module derives this too, for the
  # routes it is given; it is repeated here because the guardrail on a
  # hand-written nexthop has to know which addresses are ours before the module
  # is called. `try` because a malformed prefix must reach the operator as the
  # validation message on the variable, not as a cidrhost error inside this file.
  customer_addresses_by_key = {
    for key, address in local.interface_addresses_by_key : key => try(
      cidrhost(address, 0) == split("/", address)[0] ? cidrhost(address, 1) : cidrhost(address, 0),
      null
    )
  }

  customer_addresses6_by_key = {
    for key, address in local.interface_addresses6_by_key : key => try(
      cidrhost(address, 0) == split("/", address)[0] ? cidrhost(address, 1) : cidrhost(address, 0),
      null
    )
  }

  # Health checks are declared for every tunnel rather than left to Cloudflare's
  # defaults, so that turning one off in the dashboard shows up as drift on the
  # next plan. A tunnel that is not health checked is never withdrawn from the
  # routing table when it fails.
  health_check_states = merge(
    {
      for key, tunnel in var.wan_gre_tunnels :
      "wan_gre_tunnels.${key}" => coalesce(tunnel.health_check_enabled, var.default_tunnel_health_check_enabled)
    },
    {
      for key, tunnel in var.wan_ipsec_tunnels :
      "wan_ipsec_tunnels.${key}" => coalesce(tunnel.health_check_enabled, var.default_tunnel_health_check_enabled)
    },
  )

  # Tunnels that peer rather than being routed statically. Used to spot an MD5
  # key supplied for a tunnel that runs no BGP session.
  bgp_tunnel_keys = concat(
    [for key, tunnel in var.wan_gre_tunnels : key if tunnel.bgp_customer_asn != null],
    [for key, tunnel in var.wan_ipsec_tunnels : key if tunnel.bgp_customer_asn != null],
  )

  # Module inputs
  #
  # Per-tunnel settings win; anything unset falls back to the platform baseline.
  # coalesce is deliberately not used for the values that default to null
  gre_tunnels = [
    for key, tunnel in var.wan_gre_tunnels : {
      name                = tunnel.name
      description         = tunnel.description
      cloudflare_endpoint = tunnel.cloudflare_endpoint
      customer_endpoint   = tunnel.customer_endpoint
      interface_address   = tunnel.interface_address
      interface_address6  = tunnel.interface_address6

      mtu                      = tunnel.mtu != null ? tunnel.mtu : var.default_gre_tunnel_mtu
      ttl                      = tunnel.ttl != null ? tunnel.ttl : var.default_gre_tunnel_ttl
      automatic_return_routing = tunnel.automatic_return_routing != null ? tunnel.automatic_return_routing : var.default_automatic_return_routing

      health_check = {
        enabled   = coalesce(tunnel.health_check_enabled, var.default_tunnel_health_check_enabled)
        direction = coalesce(tunnel.health_check_direction, var.default_tunnel_health_check_direction)
        rate      = coalesce(tunnel.health_check_rate, var.default_tunnel_health_check_rate)
        type      = coalesce(tunnel.health_check_type, var.default_tunnel_health_check_type)
        target    = tunnel.health_check_target
      }

      # The MD5 key is merged in from the pipeline environment
      bgp = tunnel.bgp_customer_asn == null ? null : {
        customer_asn   = tunnel.bgp_customer_asn
        extra_prefixes = tunnel.bgp_extra_prefixes
        md5_key        = lookup(var.wan_bgp_md5_keys, key, null)
      }
    }
  ]

  ipsec_tunnels = [
    for key, tunnel in var.wan_ipsec_tunnels : {
      name                = tunnel.name
      description         = tunnel.description
      cloudflare_endpoint = tunnel.cloudflare_endpoint
      customer_endpoint   = tunnel.customer_endpoint
      interface_address   = tunnel.interface_address
      interface_address6  = tunnel.interface_address6

      # From the environment. No entry means Cloudflare generates a PSK.
      psk = lookup(var.wan_ipsec_tunnel_psks, key, null)

      replay_protection            = tunnel.replay_protection != null ? tunnel.replay_protection : var.default_ipsec_replay_protection
      automatic_return_routing     = tunnel.automatic_return_routing != null ? tunnel.automatic_return_routing : var.default_automatic_return_routing
      custom_remote_identity_label = tunnel.custom_remote_identity_label

      health_check = {
        enabled   = coalesce(tunnel.health_check_enabled, var.default_tunnel_health_check_enabled)
        direction = coalesce(tunnel.health_check_direction, var.default_tunnel_health_check_direction)
        rate      = coalesce(tunnel.health_check_rate, var.default_tunnel_health_check_rate)
        type      = coalesce(tunnel.health_check_type, var.default_tunnel_health_check_type)
        target    = tunnel.health_check_target
      }

      bgp = tunnel.bgp_customer_asn == null ? null : {
        customer_asn   = tunnel.bgp_customer_asn
        extra_prefixes = tunnel.bgp_extra_prefixes
        md5_key        = lookup(var.wan_bgp_md5_keys, key, null)
      }
    }
  ]

  # `if contains(...)` rather than a bare index: a tunnel_key pointing at nothing
  # must reach the operator as the preflight message naming it, not as an
  # "Invalid index" against this file or as the module complaining that a route
  # names neither a tunnel nor a next hop.
  static_routes = [
    for key, route in var.wan_static_routes : {
      prefix       = route.prefix
      priority     = route.priority != null ? route.priority : var.default_static_route_priority
      nexthop      = route.nexthop
      tunnel_name  = route.tunnel_key == null ? null : local.tunnel_names_by_key[route.tunnel_key]
      weight       = route.weight
      description  = route.description
      colo_names   = route.colo_names
      colo_regions = route.colo_regions
    }
    if route.tunnel_key == null || contains(keys(local.tunnel_names_by_key), route.tunnel_key)
  ]

  # Preflight checks here
  #
  # One logical key cannot name both a GRE and an IPsec tunnel: the two maps are
  # merged to resolve a route's tunnel_key, and the second would silently win.
  keys_in_both_tunnel_maps = sort(setintersection(
    toset(keys(var.wan_gre_tunnels)),
    toset(keys(var.wan_ipsec_tunnels)),
  ))

  dangling_tunnel_keys = sort(distinct([
    for key, route in var.wan_static_routes : "wan_static_routes.${key} -> tunnel_key = \"${route.tunnel_key}\""
    if route.tunnel_key != null && !contains(keys(local.tunnel_names_by_key), route.tunnel_key)
  ]))

  # Only the keys of the secret maps are read, never a value, so nothing
  # sensitive can reach a preflight message.
  ipsec_psk_keys = nonsensitive(keys(var.wan_ipsec_tunnel_psks))

  orphaned_ipsec_psks = sort([
    for key in local.ipsec_psk_keys : key
    if !contains(keys(var.wan_ipsec_tunnels), key)
  ])

  bgp_md5_key_names = nonsensitive(keys(var.wan_bgp_md5_keys))

  orphaned_bgp_md5_keys = sort([
    for key in local.bgp_md5_key_names : key
    if !contains(local.bgp_tunnel_keys, key)
  ])

  # Governing defaults. Each of these is a configuration Cloudflare accepts
  # happily, and that quietly costs an estate either its failover or its traffic.
  tunnels_without_health_checks = var.allow_tunnels_without_health_checks ? [] : sort([
    for path, enabled in local.health_check_states : path if !enabled
  ])

  default_route_prefixes = ["0.0.0.0/0", "::/0"]

  default_routes = var.allow_default_static_route ? [] : sort([
    for key, route in var.wan_static_routes : "wan_static_routes.${key} (${route.prefix})"
    if contains(local.default_route_prefixes, trimspace(route.prefix))
  ])

  # RFC 1918, RFC 6598 carrier-grade NAT space, and IPv6 unique-local. The
  # default route is excluded because it has a gate of its own and reporting it
  # under both reads as two separate problems.
  public_prefix_routes = var.allow_public_static_route_prefixes ? [] : sort([
    for key, route in var.wan_static_routes : "wan_static_routes.${key} (${route.prefix})"
    if !contains(local.default_route_prefixes, trimspace(route.prefix))
    && !can(regex("^(10\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|100\\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\\.|[fF][cCdD])", trimspace(route.prefix)))
  ])

  # Counted on the tunnel or next hop each route points at, so two routes for one
  # prefix down the same tunnel do not read as redundancy.
  route_targets_by_prefix = {
    for key, route in var.wan_static_routes :
    lower(trimspace(route.prefix)) => coalesce(route.tunnel_key, route.nexthop)...
  }

  single_tunnel_prefixes = var.allow_single_tunnel_prefixes ? [] : sort([
    for prefix, targets in local.route_targets_by_prefix : prefix
    if length(distinct(targets)) < 2
  ])

  managed_tunnel_addresses = [
    for address in concat(
      values(local.customer_addresses_by_key),
      values(local.customer_addresses6_by_key),
    ) : address if address != null
  ]

  unmanaged_nexthop_routes = var.allow_static_routes_to_unmanaged_nexthops ? [] : sort([
    for key, route in var.wan_static_routes : "wan_static_routes.${key} (nexthop ${route.nexthop})"
    if route.nexthop != null && !contains(local.managed_tunnel_addresses, route.nexthop)
  ])
}
