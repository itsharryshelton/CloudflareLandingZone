resource "terraform_data" "preflight" {
  input = {
    tunnels          = length(var.cloudflare_tunnels)
    virtual_networks = length(var.tunnel_virtual_networks)
    routes           = length(var.tunnel_routes)
    referenced_zones = length(local.referenced_zones)
  }

  lifecycle {
    precondition {
      condition     = length(local.dangling_zone_keys) == 0
      error_message = "zone_key does not match any entry in var.zones: ${join("; ", local.dangling_zone_keys)}. Valid keys: ${join(", ", sort(keys(var.zones)))}. Both layers must be given the same accounts/<account>/zones.tfvars."
    }

    precondition {
      condition     = length(local.hostnames_outside_zone) == 0
      error_message = "A tunnel hostname is not inside the zone it references: ${join("; ", local.hostnames_outside_zone)}. Cloudflare would create the tunnel and its ingress rule, then refuse the DNS record, leaving a hostname the tunnel answers for and nothing routes to."
    }

    precondition {
      condition     = length(local.locally_managed_with_ingress) == 0
      error_message = "These tunnels are locally managed but declare ingress rules: ${join(", ", local.locally_managed_with_ingress)}. A locally managed connector takes its rules from config.yml on its own host and ignores these. Remove the rules, or set config_src = \"cloudflare\"."
    }

    precondition {
      condition     = length(local.dangling_route_tunnel_keys) == 0
      error_message = "tunnel_key does not match any entry in cloudflare_tunnels: ${join("; ", local.dangling_route_tunnel_keys)}. Valid keys: ${join(", ", sort(keys(var.cloudflare_tunnels)))}."
    }

    precondition {
      condition     = length(local.dangling_virtual_network_keys) == 0
      error_message = "virtual_network_key does not match any entry in tunnel_virtual_networks: ${join("; ", local.dangling_virtual_network_keys)}. Valid keys: ${join(", ", sort(keys(var.tunnel_virtual_networks)))}. Use virtual_network_id for one managed outside this layer, or neither for the account's default."
    }

    precondition {
      condition     = length(local.no_tls_verify_rules) == 0
      error_message = "These origin settings switch off certificate verification: ${join("; ", local.no_tls_verify_rules)}. The hop from connector to origin stays encrypted but is no longer authenticated, so anything able to answer on that address is trusted. Point ca_pool at the origin's CA or set origin_server_name, or set allow_no_tls_verify = true in layers/tunnels/defaults.auto.tfvars on a pull request that says why."
    }

    precondition {
      condition     = length(local.unmanaged_hostnames) == 0
      error_message = "These ingress rules name no zone_key, so no DNS record will point at the tunnel: ${join("; ", local.unmanaged_hostnames)}. The hostname would look configured and never receive a request. Add the zone_key from zones.tfvars, or set allow_unmanaged_tunnel_hostnames = true in layers/tunnels/defaults.auto.tfvars if the record really is managed elsewhere."
    }

    precondition {
      condition     = length(local.default_routes) == 0
      error_message = "These tunnel routes carry the default route: ${join("; ", local.default_routes)}. Every destination WARP has no more specific route for would leave through one connector, making that site the internet egress for every enrolled device. List the ranges the site owns, or set allow_default_tunnel_route = true in layers/tunnels/defaults.auto.tfvars if that egress is the design."
    }

    precondition {
      condition     = length(local.public_prefix_routes) == 0
      error_message = "These tunnel routes name a range outside private address space: ${join("; ", local.public_prefix_routes)}. Private network routes are for RFC 1918, RFC 6598 or IPv6 unique-local ranges; a public one pulls traffic for somebody else's address space down a connector. Set allow_public_tunnel_route_prefixes = true in layers/tunnels/defaults.auto.tfvars if the range really is meant to egress there."
    }
  }
}
