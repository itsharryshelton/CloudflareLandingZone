# DNS records for a zone this module does not own.
#
# zone_base creates a zone and can manage records in it, which is the right
# shape for a small estate: one module, one state, one apply. It stops being the right shape at scale - can cause pipelines to run for a long time if large estate in testing
#
# Splitting DNS into its own layer and state means a DNS change refreshes DNS
# and nothing else, and a zone-settings change refreshes settings and nothing
# else. This is why this module takes `zone_id` rather than a domain to create.
#
# The normalisation and keying below is deliberately identical to zone_base
resource "cloudflare_dns_record" "this" {
  for_each = local.records

  zone_id  = var.zone_id
  name     = each.value.name
  type     = each.value.type
  content  = each.value.content
  ttl      = each.value.ttl
  proxied  = each.value.proxied
  priority = each.value.priority
  comment  = each.value.comment
  tags     = each.value.tags

  lifecycle {
    precondition {
      condition     = length(local.duplicate_keys) == 0
      error_message = "records contains duplicate type/name/content combinations: ${join(", ", local.duplicate_keys)}. Names are compared fully-qualified, so \"www\" and \"www.${var.domain_name}\" collide - each record must be unique."
    }
  }
}
