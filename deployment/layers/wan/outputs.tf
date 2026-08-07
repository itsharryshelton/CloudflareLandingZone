output "gre_tunnels" {
  description = "Per-GRE-tunnel identifiers and addressing, keyed on tunnel name. `customer_interface_address` is what the device at the customer end takes from the /31, and what its own tunnel interface must be configured with."
  value       = module.wan.gre_tunnels
}

output "ipsec_tunnels" {
  description = "Per-IPsec-tunnel identifiers and addressing, keyed on tunnel name. No pre-shared key: a credential does not belong in an output, which ends up in a plan comment on a pull request. `psk_last_generated_on` is the closest thing available - it moves when the key changes."
  value       = module.wan.ipsec_tunnels
}

output "static_routes" {
  description = "Static route IDs and resolved next hops, keyed on \"<prefix> via <next hop>\". Read this after an apply to confirm each route points at the customer end of its tunnel rather than Cloudflare's."
  value       = module.wan.static_routes
}

output "bgp_status" {
  description = "BGP session state per tunnel name, for the tunnels that peer rather than being routed statically. Empty for a statically routed estate. Anything other than \"BGP_UP\" more than a minute or two after an apply is the customer device, not this layer."
  value       = module.wan.bgp_status
}

output "tunnel_names_by_key" {
  description = "Logical key => Cloudflare tunnel name, for both tunnel types. The translation between what an account tree says and what the dashboard shows."
  value       = local.tunnel_names_by_key
}
