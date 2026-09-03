# DNS records
#
# Downstream deployments pin an immutable tag instead of the local path:
#   source = "git::https://github.com/Your-Org/cloudflare-platform-modules//dns_records?ref=v1.0.0"
module "dns" {
  source = "git::https://github.com/Your-Org/cloudflare-platform-modules//dns_records"

  for_each = local.zones_with_records

  zone_id     = data.cloudflare_zone.this[each.key].zone_id
  domain_name = each.value.domain_name

  records = each.value.dns_records
}
