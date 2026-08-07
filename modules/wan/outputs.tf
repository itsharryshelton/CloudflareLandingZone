output "gre_tunnels" {
  description = "Per-GRE-tunnel identifiers and addressing, keyed on tunnel name. `customer_interface_address` is the address the device at your end takes from the /31, and the one a static route's next hop has to be."
  value = {
    for name, tunnel in cloudflare_magic_wan_gre_tunnel.this : name => {
      id                           = tunnel.id
      cloudflare_endpoint          = tunnel.cloudflare_gre_endpoint
      customer_endpoint            = tunnel.customer_gre_endpoint
      interface_address            = tunnel.interface_address
      customer_interface_address   = local.customer_side_addresses[name]
      cloudflare_interface_address = local.cloudflare_side_addresses[name]
      mtu                          = tunnel.mtu
      created_on                   = tunnel.created_on
    }
  }
}

output "ipsec_tunnels" {
  description = "Per-IPsec-tunnel identifiers and addressing, keyed on tunnel name. Deliberately carries no PSK: the key is a credential, and an output ends up in a plan comment on a pull request."
  value = {
    for name, tunnel in cloudflare_magic_wan_ipsec_tunnel.this : name => {
      id                           = tunnel.id
      cloudflare_endpoint          = tunnel.cloudflare_endpoint
      customer_endpoint            = tunnel.customer_endpoint
      interface_address            = tunnel.interface_address
      customer_interface_address   = local.customer_side_addresses[name]
      cloudflare_interface_address = local.cloudflare_side_addresses[name]
      allow_null_cipher            = tunnel.allow_null_cipher
      psk_last_generated_on        = try(tunnel.psk_metadata.last_generated_on, null)
      created_on                   = tunnel.created_on
    }
  }
}

output "static_routes" {
  description = "Static route IDs and their resolved next hops, keyed on \"<prefix> via <next hop>\". Read this to confirm a route points at the customer end of a tunnel rather than Cloudflare's."
  value = {
    for key, route in cloudflare_magic_wan_static_route.this : key => {
      id       = route.id
      prefix   = route.prefix
      nexthop  = route.nexthop
      priority = route.priority
    }
  }
}

output "bgp_status" {
  description = "BGP session state per tunnel name, for the tunnels that peer rather than being routed statically. Empty for a statically routed estate. \"BGP_ESTABLISHING\" for more than a minute or two after an apply means the customer device has not accepted the session."
  value = {
    for name, status in merge(
      { for key, tunnel in cloudflare_magic_wan_gre_tunnel.this : key => tunnel.bgp_status if tunnel.bgp != null },
      { for key, tunnel in cloudflare_magic_wan_ipsec_tunnel.this : key => tunnel.bgp_status if tunnel.bgp != null },
    ) : name => try(status.state, null)
  }
}
