# Applies the platform baseline, resolves zone, tunnel and virtual network keys
# to what the module works in, and derives the preflight assertions, so that
# tunnels.tf reads as a plain module call.

locals {
  # Only zones a public hostname actually targets are looked up, so a deployment
  # of private-network tunnels costs no API call.
  referenced_zone_keys = distinct(flatten([
    for tunnel in var.cloudflare_tunnels : [for rule in tunnel.ingress : rule.zone_key if rule.zone_key != null]
  ]))

  referenced_zones = {
    for key, zone in var.zones : key => zone
    if contains(local.referenced_zone_keys, key)
  }

  # Key -> Cloudflare name
  tunnel_names_by_key          = { for key, tunnel in var.cloudflare_tunnels : key => tunnel.name }
  virtual_network_names_by_key = { for key, network in var.tunnel_virtual_networks : key => network.name }

  tunnel_config_sources = {
    for key, tunnel in var.cloudflare_tunnels : key => coalesce(tunnel.config_src, var.default_tunnel_config_src)
  }

  # Module inputs
  tunnels = [
    for key, tunnel in var.cloudflare_tunnels : {
      name              = tunnel.name
      config_src        = local.tunnel_config_sources[key]
      catch_all_service = coalesce(tunnel.catch_all_service, var.default_catch_all_service)
      origin_request    = tunnel.origin_request

      ingress = [
        for rule in tunnel.ingress : {
          hostname       = rule.hostname
          path           = rule.path
          service        = rule.service
          origin_request = rule.origin_request
          zone_id        = rule.zone_key == null ? null : try(data.cloudflare_zone.this[rule.zone_key].id, null)
        }
      ]
    }
  ]

  virtual_networks = [
    for key, network in var.tunnel_virtual_networks : {
      name               = network.name
      comment            = network.comment
      is_default_network = network.is_default_network
    }
  ]

  # Routes whose keys resolve to nothing are left out, and reported by preflight.
  routes = [
    for key, route in var.tunnel_routes : {
      network              = route.network
      comment              = route.comment
      tunnel_name          = local.tunnel_names_by_key[route.tunnel_key]
      virtual_network_name = route.virtual_network_key == null ? null : local.virtual_network_names_by_key[route.virtual_network_key]
      virtual_network_id   = route.virtual_network_id
    }
    if contains(keys(local.tunnel_names_by_key), route.tunnel_key)
    && (route.virtual_network_key == null ? true : contains(keys(local.virtual_network_names_by_key), route.virtual_network_key))
  ]

  # Derived assertions, consumed by preflight.tf

  dangling_zone_keys = sort(distinct(flatten([
    for key, tunnel in var.cloudflare_tunnels : [
      for index, rule in tunnel.ingress : "cloudflare_tunnels.${key}.ingress[${index}] -> zone_key = \"${rule.zone_key}\""
      if rule.zone_key == null ? false : !contains(keys(var.zones), rule.zone_key)
    ]
  ])))

  # Cloudflare would create the tunnel and its configuration, then refuse the
  # record, leaving a hostname the tunnel answers for and nothing routes to.
  hostnames_outside_zone = sort(flatten([
    for key, tunnel in var.cloudflare_tunnels : [
      for index, rule in tunnel.ingress :
      "cloudflare_tunnels.${key}.ingress[${index}]: \"${rule.hostname}\" is not within \"${var.zones[rule.zone_key].domain_name}\""
      if rule.zone_key == null ? false : (
        contains(keys(var.zones), rule.zone_key)
        ? !(
          lower(trimspace(rule.hostname)) == lower(var.zones[rule.zone_key].domain_name)
          || endswith(lower(trimspace(rule.hostname)), ".${lower(var.zones[rule.zone_key].domain_name)}")
        )
        : false
      )
    ]
  ]))

  locally_managed_with_ingress = sort([
    for key, tunnel in var.cloudflare_tunnels : "cloudflare_tunnels.${key}"
    if local.tunnel_config_sources[key] == "local" && length(tunnel.ingress) > 0
  ])

  dangling_route_tunnel_keys = sort([
    for key, route in var.tunnel_routes : "tunnel_routes.${key} -> tunnel_key = \"${route.tunnel_key}\""
    if !contains(keys(var.cloudflare_tunnels), route.tunnel_key)
  ])

  dangling_virtual_network_keys = sort([
    for key, route in var.tunnel_routes : "tunnel_routes.${key} -> virtual_network_key = \"${route.virtual_network_key}\""
    if route.virtual_network_key == null ? false : !contains(keys(var.tunnel_virtual_networks), route.virtual_network_key)
  ])

  # Governing defaults. Each of these is a configuration Cloudflare accepts
  # happily, and that quietly publishes or reroutes more than anybody meant.
  no_tls_verify_rules = var.allow_no_tls_verify ? [] : sort(concat(
    [
      for key, tunnel in var.cloudflare_tunnels : "cloudflare_tunnels.${key}.origin_request"
      if try(tunnel.origin_request.no_tls_verify, null) == true
    ],
    flatten([
      for key, tunnel in var.cloudflare_tunnels : [
        for index, rule in tunnel.ingress : "cloudflare_tunnels.${key}.ingress[${index}] (${rule.hostname})"
        if try(rule.origin_request.no_tls_verify, null) == true
      ]
    ]),
  ))

  unmanaged_hostnames = var.allow_unmanaged_tunnel_hostnames ? [] : sort(flatten([
    for key, tunnel in var.cloudflare_tunnels : [
      for index, rule in tunnel.ingress : "cloudflare_tunnels.${key}.ingress[${index}] (${rule.hostname})"
      if rule.zone_key == null
    ]
  ]))

  default_route_prefixes = ["0.0.0.0/0", "::/0"]

  default_routes = var.allow_default_tunnel_route ? [] : sort([
    for key, route in var.tunnel_routes : "tunnel_routes.${key} (${route.network})"
    if contains(local.default_route_prefixes, trimspace(route.network))
  ])

  # RFC 1918, RFC 6598 carrier-grade NAT space, and IPv6 unique-local. The
  # default route is excluded because it has a gate of its own.
  public_prefix_routes = var.allow_public_tunnel_route_prefixes ? [] : sort([
    for key, route in var.tunnel_routes : "tunnel_routes.${key} (${route.network})"
    if !contains(local.default_route_prefixes, trimspace(route.network))
    && !can(regex("^(10\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|100\\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\\.|[fF][cCdD])", trimspace(route.network)))
  ])
}
