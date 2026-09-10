locals {
  # Collections, keyed on the Cloudflare-visible name
  tunnels     = { for tunnel in var.tunnels : lower(trimspace(tunnel.name)) => tunnel }
  tunnel_keys = keys(local.tunnels)

  configured_tunnels = {
    for key, tunnel in local.tunnels : key => tunnel if tunnel.config_src == "cloudflare"
  }

  virtual_networks     = { for network in var.virtual_networks : lower(trimspace(network.name)) => network }
  virtual_network_keys = keys(local.virtual_networks)

  # Origin request settings
  origin_request_inputs = merge(
    {
      for key, tunnel in local.configured_tunnels : "tunnel:${key}" => tunnel.origin_request
      if tunnel.origin_request != null
    },
    merge([
      for key, tunnel in local.configured_tunnels : {
        for index, rule in tunnel.ingress : "rule:${key}:${index}" => rule.origin_request
        if rule.origin_request != null
      }
    ]...),
  )

  origin_requests = {
    for path, request in local.origin_request_inputs : path => {
      access = request.access == null ? null : {
        team_name = lower(trimspace(request.access.team_name))
        aud_tag   = request.access.aud_tags
        required  = request.access.required
      }
      ca_pool                  = request.ca_pool
      connect_timeout          = request.connect_timeout
      disable_chunked_encoding = request.disable_chunked_encoding
      http2_origin             = request.http2_origin
      http_host_header         = request.http_host_header
      keep_alive_connections   = request.keep_alive_connections
      keep_alive_timeout       = request.keep_alive_timeout
      match_sn_ito_host        = request.match_sni_to_host
      no_happy_eyeballs        = request.no_happy_eyeballs
      no_tls_verify            = request.no_tls_verify
      origin_server_name       = request.origin_server_name
      proxy_type               = request.proxy_type
      tcp_keep_alive           = request.tcp_keep_alive
      tls_timeout              = request.tls_timeout
    }
  }

  # Ingress
  tunnel_ingress = {
    for key, tunnel in local.configured_tunnels : key => concat(
      [
        for index, rule in tunnel.ingress : {
          hostname       = lower(trimspace(rule.hostname))
          path           = rule.path
          service        = trimspace(rule.service)
          origin_request = try(local.origin_requests["rule:${key}:${index}"], null)
        }
      ],
      [
        {
          hostname       = null
          path           = null
          service        = trimspace(tunnel.catch_all_service)
          origin_request = null
        }
      ],
    )
  }

  # One CNAME per public hostname
  dns_record_groups = merge([
    for key, tunnel in local.configured_tunnels : {
      for rule in tunnel.ingress : lower(trimspace(rule.hostname)) => {
        tunnel_key = key
        zone_id    = rule.zone_id
      }...
      if rule.zone_id != null
    }
  ]...)

  dns_records = { for hostname, entries in local.dns_record_groups : hostname => entries[0] }

  # Routes
  routes_normalised = [
    for route in var.routes : {
      network             = trimspace(route.network)
      tunnel_key          = lower(trimspace(route.tunnel_name))
      virtual_network_key = route.virtual_network_name == null ? null : lower(trimspace(route.virtual_network_name))
      virtual_network_id  = route.virtual_network_id
      comment             = route.comment
      scope = (
        route.virtual_network_name != null ? "vnet/${lower(trimspace(route.virtual_network_name))}"
        : route.virtual_network_id != null ? "vnet-id/${route.virtual_network_id}"
        : "default"
      )
    }
  ]

  routes_grouped = { for route in local.routes_normalised : "${route.network} in ${route.scope}" => route... }
  routes         = { for key, routes in local.routes_grouped : key => routes[0] }

  # Derived assertions, consumed by the preconditions in main.tf
  duplicate_routes = sort([for key, routes in local.routes_grouped : key if length(routes) > 1])

  unknown_route_tunnels = sort(distinct([
    for route in local.routes_normalised : "${route.network} -> tunnel_name = \"${route.tunnel_key}\""
    if !contains(local.tunnel_keys, route.tunnel_key)
  ]))

  unknown_route_virtual_networks = sort(distinct([
    for route in local.routes_normalised : "${route.network} -> virtual_network_name = \"${route.virtual_network_key}\""
    if route.virtual_network_key == null ? false : !contains(local.virtual_network_keys, route.virtual_network_key)
  ]))
}
