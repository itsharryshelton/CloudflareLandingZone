locals {
  # Tunnels, keyed on the Cloudflare-visible name.
  gre_tunnels_grouped = { for tunnel in var.gre_tunnels : tunnel.name => tunnel... }
  gre_tunnels         = { for name, tunnels in local.gre_tunnels_grouped : name => tunnels[0] }

  ipsec_tunnels_grouped = { for tunnel in var.ipsec_tunnels : tunnel.name => tunnel... }
  ipsec_tunnels         = { for name, tunnels in local.ipsec_tunnels_grouped : name => tunnels[0] }

  # GRE and IPsec tunnels share one name space on the account, so uniqueness is checked across both lists rather than within each.
  tunnel_names = concat(
    [for tunnel in var.gre_tunnels : tunnel.name],
    [for tunnel in var.ipsec_tunnels : tunnel.name],
  )

  duplicate_tunnel_names = [
    for name in distinct(local.tunnel_names) : name
    if length([for candidate in local.tunnel_names : candidate if candidate == name]) > 1
  ]

  # Health checks
  # The operator writes `target` as a plain address; the API takes an object,
  # where the saved value is what you asked for and the effective value is what
  # Cloudflare computed when you asked for nothing. Only `saved` is settable.
  gre_health_checks = {
    for name, tunnel in local.gre_tunnels : name => tunnel.health_check == null ? null : {
      enabled   = tunnel.health_check.enabled
      direction = tunnel.health_check.direction
      rate      = tunnel.health_check.rate
      type      = tunnel.health_check.type
      target    = tunnel.health_check.target == null ? null : { saved = tunnel.health_check.target }
    }
  }

  ipsec_health_checks = {
    for name, tunnel in local.ipsec_tunnels : name => tunnel.health_check == null ? null : {
      enabled   = tunnel.health_check.enabled
      direction = tunnel.health_check.direction
      rate      = tunnel.health_check.rate
      type      = tunnel.health_check.type
      target    = tunnel.health_check.target == null ? null : { saved = tunnel.health_check.target }
    }
  }

  # BGP sessions. Every field is spelled out, null included, so that the object
  # type is identical across tunnels whatever each one sets.
  gre_bgp = {
    for name, tunnel in local.gre_tunnels : name => tunnel.bgp == null ? null : {
      customer_asn   = tunnel.bgp.customer_asn
      extra_prefixes = tunnel.bgp.extra_prefixes
      md5_key        = tunnel.bgp.md5_key
    }
  }

  ipsec_bgp = {
    for name, tunnel in local.ipsec_tunnels : name => tunnel.bgp == null ? null : {
      customer_asn   = tunnel.bgp.customer_asn
      extra_prefixes = tunnel.bgp.extra_prefixes
      md5_key        = tunnel.bgp.md5_key
    }
  }

  # A custom IKE identity has to be of the form
  # <label>.<account id>.custom.ipsec.cloudflare.com. The account ID is the part
  # nobody remembers correctly, so the module assembles it.
  ipsec_custom_remote_identities = {
    for name, tunnel in local.ipsec_tunnels : name => tunnel.custom_remote_identity_label == null ? null : {
      fqdn_id = "${tunnel.custom_remote_identity_label}.${var.account_id}.custom.ipsec.cloudflare.com"
    }
  }

  # Tunnel addressing
  # `interface_address` is Cloudflare's own address within the /31; the customer
  # device takes the other host, and that address - not the one written - is what
  # a static route's next hop must be. Deriving it from the written address means
  # the arithmetic is right whichever of the two an operator happened to type,
  # because Cloudflare claims the one it is given either way.
  #
  # Normalised to one shape across both tunnel types on purpose: merging the two
  # maps raw would produce a value whose type differs per key, and every check
  # below only needs the fields the two have in common.
  all_tunnels = merge(
    {
      for name, tunnel in local.gre_tunnels : name => {
        type               = "gre_tunnels"
        interface_address  = tunnel.interface_address
        interface_address6 = tunnel.interface_address6
        health_check       = tunnel.health_check
      }
    },
    {
      for name, tunnel in local.ipsec_tunnels : name => {
        type               = "ipsec_tunnels"
        interface_address  = tunnel.interface_address
        interface_address6 = tunnel.interface_address6
        health_check       = tunnel.health_check
      }
    },
  )

  cloudflare_side_addresses = {
    for name, tunnel in local.all_tunnels : name => split("/", tunnel.interface_address)[0]
  }

  customer_side_addresses = {
    for name, tunnel in local.all_tunnels : name => (
      cidrhost(tunnel.interface_address, 0) == local.cloudflare_side_addresses[name]
      ? cidrhost(tunnel.interface_address, 1)
      : cidrhost(tunnel.interface_address, 0)
    )
  }

  customer_side_addresses6 = {
    for name, tunnel in local.all_tunnels : name => tunnel.interface_address6 == null ? null : (
      cidrhost(tunnel.interface_address6, 0) == split("/", tunnel.interface_address6)[0]
      ? cidrhost(tunnel.interface_address6, 1)
      : cidrhost(tunnel.interface_address6, 0)
    )
  }

  # Compared on the network address rather than on the string, so that
  # "10.252.0.0/31" and "10.252.0.1/31" - the same two hosts written from either
  # end - are recognised as the one subnet.
  interface_networks = {
    for name, tunnel in local.all_tunnels : name => cidrhost(tunnel.interface_address, 0)
  }

  overlapping_interface_addresses = sort(distinct(flatten([
    for name, network in local.interface_networks : [
      for other, other_network in local.interface_networks :
      "${join(" and ", sort([name, other]))} both use ${network}/31"
      if other != name && other_network == network
    ]
  ])))

  # Static routes
  # A route referencing a tunnel that does not exist, or an IPv6 prefix over a
  # tunnel with no IPv6 addressing, leaves the next hop unresolved. It falls back
  # to a placeholder naming the tunnel it wanted, so that the key below stays
  # interpolatable and unique - two unresolved routes are not a duplicate - and
  # the failure reaches the operator as a precondition rather than as an error
  # inside this file.
  static_routes_resolved = [
    for route in var.static_routes : merge(route, {
      nexthop = (
        route.nexthop != null
        ? route.nexthop
        : coalesce(
          can(regex(":", route.prefix))
          ? try(local.customer_side_addresses6[route.tunnel_name], null)
          : try(local.customer_side_addresses[route.tunnel_name], null),
          "unresolved tunnel ${coalesce(route.tunnel_name, "")}"
        )
      )
    })
  ]

  # Keyed on prefix and next hop: the pair is what makes a route distinct, and it
  # is stable, so reordering the list never proposes a replacement.
  static_routes_grouped = {
    for route in local.static_routes_resolved :
    "${route.prefix} via ${route.nexthop}" => route...
  }

  static_routes = {
    for key, routes in local.static_routes_grouped : key => {
      prefix      = routes[0].prefix
      nexthop     = routes[0].nexthop
      priority    = routes[0].priority
      weight      = routes[0].weight
      description = routes[0].description

      scope = (
        length(routes[0].colo_names) + length(routes[0].colo_regions) == 0 ? null : {
          colo_names   = length(routes[0].colo_names) > 0 ? routes[0].colo_names : null
          colo_regions = length(routes[0].colo_regions) > 0 ? routes[0].colo_regions : null
        }
      )
    }
  }

  duplicate_static_routes = [
    for key, routes in local.static_routes_grouped : key if length(routes) > 1
  ]

  # Guardrail inputs
  routes_naming_unknown_tunnels = sort(distinct([
    for route in var.static_routes : "${route.prefix} -> tunnel_name = \"${route.tunnel_name}\""
    if route.tunnel_name != null && !contains(keys(local.all_tunnels), coalesce(route.tunnel_name, ""))
  ]))

  ipv6_routes_over_ipv4_only_tunnels = sort(distinct([
    for route in var.static_routes : "${route.prefix} -> ${route.tunnel_name}"
    if route.tunnel_name != null
    && can(regex(":", route.prefix))
    && contains(keys(local.all_tunnels), coalesce(route.tunnel_name, ""))
    && try(local.customer_side_addresses6[route.tunnel_name], null) == null
  ]))

  # Routing to Cloudflare's own end of the /31 rather than to the customer
  # device's. Cloudflare accepts the route and the dashboard shows it as healthy.
  routes_to_cloudflare_side = sort(distinct(flatten([
    for route in var.static_routes : [
      for name, address in local.cloudflare_side_addresses :
      "${route.prefix} -> ${route.nexthop} is the Cloudflare side of ${name} (${local.all_tunnels[name].interface_address})"
      if route.nexthop == address
    ]
    if route.nexthop != null
  ])))

  # Whether a tunnel may run without health checks at all is a policy question
  # rather than a correctness one, so it is gated in the layer
  # (allow_tunnels_without_health_checks) rather than refused here.
  health_checks_with_ignored_targets = sort([
    for name, tunnel in local.all_tunnels : "${tunnel.type}.${name}"
    if tunnel.health_check != null
    && tunnel.health_check.direction == "bidirectional"
    && tunnel.health_check.target != null
  ])
}
