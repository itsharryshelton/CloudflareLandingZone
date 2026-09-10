output "tunnels" {
  description = "Tunnel ID, name, configuration source, CNAME target and status, keyed by normalised tunnel name. No token: fetch it when installing a connector, from the dashboard or `cloudflared tunnel token <id>`. `status` stays \"inactive\" until a connector runs."
  value       = module.tunnel.tunnels
}

output "virtual_networks" {
  description = "Virtual network ID per normalised name. The ID an Access application's private destination, or a WARP profile, needs to scope to that network."
  value       = module.tunnel.virtual_network_ids
}

output "routes" {
  description = "Route ID, network, tunnel ID and virtual network ID, keyed on \"<network> in <virtual network>\"."
  value       = module.tunnel.routes
}

output "public_hostnames" {
  description = "DNS record ID and tunnel per public hostname this layer created a CNAME for. Every hostname here is reachable from the internet unless an Access application in the zerotrust layer covers it."
  value       = module.tunnel.public_hostnames
}

output "tunnel_names_by_key" {
  description = "Logical key => Cloudflare tunnel name. The translation between what an account tree says and what the dashboard shows."
  value       = local.tunnel_names_by_key
}
