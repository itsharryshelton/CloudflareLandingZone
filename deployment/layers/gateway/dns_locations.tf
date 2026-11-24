# Gateway DNS locations, one module instance per site.
#
# DNS policies scope to a location by key, so the location lives beside them.
# preflight.tf holds the one rule no single instance can see: an account has
# one default location.
#
# Downstream deployments pin an immutable tag instead of the placeholder:
#   source = "git::https://github.com/Your-Org/cloudflare-platform-modules//dns_location?ref=v1.0.0"
module "dns_location" {
  source = "git::https://github.com/Your-Org/cloudflare-platform-modules//dns_location"

  for_each   = var.gateway_dns_locations
  account_id = var.cloudflare_account_id

  name                   = each.value.name
  client_default         = each.value.client_default
  ecs_support            = each.value.ecs_support
  networks               = each.value.networks
  dns_destination_ips_id = each.value.dns_destination_ips_id
  endpoints              = each.value.endpoints
  max_ttl                = each.value.max_ttl

  allow_unrestricted_endpoints = each.value.allow_unrestricted_endpoints
}
