# One Gateway DNS location: a site or network whose DNS queries Gateway
# filters and attributes to it.
#
# A location is how DNS filtering reaches something that does not run the
# Cloudflare One client - an office router, a guest network, a server estate.
# Devices on the client resolve through the account's default location, so a
# fleet that is entirely on the client needs no location managed here beyond
# that default.
#
# A DNS policy can be scoped to a location (the gateway module's
# match.dns_location_ids), which is how a guest network gets a stricter policy
# than the office it shares a building with.
resource "cloudflare_zero_trust_dns_location" "this" {
  account_id = var.account_id
  name       = var.name

  client_default         = var.client_default
  ecs_support            = var.ecs_support
  dns_destination_ips_id = var.dns_destination_ips_id

  networks  = [for cidr in var.networks : { network = cidr }]
  endpoints = local.endpoints
  max_ttl   = var.max_ttl

  lifecycle {
    precondition {
      condition     = local.enabled_endpoint_count > 0
      error_message = "Every endpoint on this location is disabled, so it receives no queries and filters nothing while appearing in the dashboard as a configured site. Enable at least one of endpoints.ipv4, ipv6, doh or dot."
    }

    precondition {
      condition     = !local.ipv4_unattributable
      error_message = "endpoints.ipv4 is enabled with no networks and no dns_destination_ips_id. On the shared Gateway IPv4 addresses a query is attributed to a location by its source address, so with no source network nothing reaching the IPv4 resolvers is this location's - its policies and logs never see it. Add the site's public egress ranges to networks, or a dedicated address pair."
    }

    precondition {
      condition     = var.allow_unrestricted_endpoints || length(local.unrestricted_endpoints) == 0
      error_message = "These endpoints answer any source: ${join(", ", local.unrestricted_endpoints)}. Each is unique to this location and answers anybody who learns its address, who then resolves through this account's DNS policies - internal names from override or resolver rules included - with their queries logged as this location's. Restrict endpoints.<name>.networks, set endpoints.doh.require_token = true, or set allow_unrestricted_endpoints = true for a location that genuinely serves roaming devices."
    }
  }
}
