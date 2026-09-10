output "tunnels" {
  description = "Tunnel ID, name, configuration source, CNAME target and status, keyed by normalised tunnel name. Deliberately carries no token: a credential does not belong in an output, which ends up in a plan comment. `status` is \"inactive\" until a connector runs."
  value = {
    for key, tunnel in cloudflare_zero_trust_tunnel_cloudflared.this : key => {
      id           = tunnel.id
      name         = tunnel.name
      config_src   = tunnel.config_src
      cname_target = "${tunnel.id}.cfargotunnel.com"
      status       = tunnel.status
    }
  }
}

output "virtual_network_ids" {
  description = "Virtual network ID per normalised virtual network name. The ID an Access application's private destination or a WARP profile needs to scope to it."
  value       = { for key, network in cloudflare_zero_trust_tunnel_cloudflared_virtual_network.this : key => network.id }
}

output "routes" {
  description = "Route ID, network, tunnel ID and virtual network ID, keyed on \"<network> in <virtual network>\"."
  value = {
    for key, route in cloudflare_zero_trust_tunnel_cloudflared_route.this : key => {
      id                 = route.id
      network            = route.network
      tunnel_id          = route.tunnel_id
      virtual_network_id = route.virtual_network_id
    }
  }
}

output "public_hostnames" {
  description = "DNS record ID and normalised tunnel name per public hostname this module created a CNAME for."
  value = {
    for hostname, record in cloudflare_dns_record.this : hostname => {
      record_id = record.id
      tunnel    = local.dns_records[hostname].tunnel_key
    }
  }
}
