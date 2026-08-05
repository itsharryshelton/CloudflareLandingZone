# Normalisation, keying and the secure-baseline merge live in locals.tf.

resource "cloudflare_zone" "this" {
  account = {
    id = var.account_id
  }
  name   = var.domain_name
  type   = var.zone_type
  paused = var.paused
}

# NOTE: cloudflare_zone_setting has no delete operation in the Cloudflare API and
# therefore cannot be destroyed. 
resource "cloudflare_zone_setting" "this" {
  for_each = local.zone_settings

  zone_id    = cloudflare_zone.this.id
  setting_id = each.key
  value      = each.value
}

resource "cloudflare_dns_record" "this" {
  for_each = local.dns_records

  zone_id  = cloudflare_zone.this.id
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
      condition     = length(local.dns_record_duplicate_keys) == 0
      error_message = "dns_records contains duplicate type/name/content combinations: ${join(", ", local.dns_record_duplicate_keys)}. Names are compared fully-qualified, so \"www\" and \"www.${var.domain_name}\" collide - each record must be unique."
    }
  }
}
