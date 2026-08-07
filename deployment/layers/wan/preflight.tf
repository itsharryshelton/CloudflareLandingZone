resource "terraform_data" "preflight" {
  input = {
    gre_tunnels   = length(var.wan_gre_tunnels)
    ipsec_tunnels = length(var.wan_ipsec_tunnels)
    static_routes = length(var.wan_static_routes)
  }

  lifecycle {
    precondition {
      condition     = length(local.keys_in_both_tunnel_maps) == 0
      error_message = "These keys name both a GRE and an IPsec tunnel: ${join(", ", local.keys_in_both_tunnel_maps)}. A static route's tunnel_key, and an entry in wan_ipsec_tunnel_psks or wan_bgp_md5_keys, is resolved against both maps at once, so one of the two would silently win. Rename one."
    }

    precondition {
      condition     = length(local.dangling_tunnel_keys) == 0
      error_message = "tunnel_key does not match any entry in wan_gre_tunnels or wan_ipsec_tunnels: ${join("; ", local.dangling_tunnel_keys)}. Valid keys: ${join(", ", sort(keys(local.tunnel_names_by_key)))}. Use nexthop for a tunnel managed outside this layer."
    }

    precondition {
      condition     = length(local.orphaned_ipsec_psks) == 0
      error_message = "wan_ipsec_tunnel_psks names keys that are not IPsec tunnels in this account: ${join(", ", local.orphaned_ipsec_psks)}. Declared IPsec tunnels: ${join(", ", sort(keys(var.wan_ipsec_tunnels)))}. A PSK against the wrong key is a live credential sitting in an environment and doing nothing, while the tunnel it was meant for came up with a key Cloudflare generated. GRE tunnels take no PSK - GRE is not encrypted."
    }

    precondition {
      condition     = length(local.orphaned_bgp_md5_keys) == 0
      error_message = "wan_bgp_md5_keys names keys that run no BGP session: ${join(", ", local.orphaned_bgp_md5_keys)}. Tunnels that peer: ${join(", ", sort(local.bgp_tunnel_keys))}. Set bgp_customer_asn on the tunnel, or drop the key."
    }

    precondition {
      condition     = length(local.tunnels_without_health_checks) == 0
      error_message = "These tunnels have health checks switched off: ${join("; ", local.tunnels_without_health_checks)}. Cloudflare withdraws an unhealthy tunnel from the Magic routing table, and that is the whole of the failover: with checks off the route stays and traffic keeps being sent into a tunnel that is down. Set allow_tunnels_without_health_checks = true in layers/wan/defaults.auto.tfvars on a pull request that says which device cannot answer a probe."
    }

    precondition {
      condition     = length(local.default_routes) == 0
      error_message = "These static routes carry the default route: ${join("; ", local.default_routes)}. Everything Cloudflare has no more specific route for would be sent towards the customer network, which matches every destination nobody thought about. List the prefixes the sites actually own, or set allow_default_static_route = true in layers/wan/defaults.auto.tfvars if on-premises internet egress is the design."
    }

    precondition {
      condition     = length(local.public_prefix_routes) == 0
      error_message = "These static routes name a prefix outside private address space: ${join("; ", local.public_prefix_routes)}. Cloudflare WAN routes between your own sites, so its prefixes are RFC 1918, RFC 6598 or IPv6 unique-local. Advertising public space through Cloudflare is Magic Transit, which is a different product and out of scope for this layer. Set allow_public_static_route_prefixes = true in layers/wan/defaults.auto.tfvars if the address space really is the customer's own private use of it."
    }

    precondition {
      condition     = length(local.single_tunnel_prefixes) == 0
      error_message = "These prefixes are reachable over exactly one tunnel: ${join(", ", local.single_tunnel_prefixes)}. One tunnel is a single point of failure with a health check attached - the check notices, and there is nowhere for the traffic to go. Add a second route down a second tunnel, or set allow_single_tunnel_prefixes = true in layers/wan/defaults.auto.tfvars for a lab or a first-tunnel bring-up."
    }

    precondition {
      condition     = length(local.unmanaged_nexthop_routes) == 0
      error_message = "These static routes name a next hop that belongs to no tunnel in this layer: ${join("; ", local.unmanaged_nexthop_routes)}. Addresses this layer's tunnels present to the customer device: ${join(", ", sort(local.managed_tunnel_addresses))}. The usual cause is an address one out - Cloudflare's own end of the /31 rather than yours - which Cloudflare accepts and then discards the traffic. Use tunnel_key and let the layer work it out, or set allow_static_routes_to_unmanaged_nexthops = true in layers/wan/defaults.auto.tfvars for a tunnel that genuinely lives elsewhere."
    }
  }
}
