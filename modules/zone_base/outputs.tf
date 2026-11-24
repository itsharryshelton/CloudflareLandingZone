output "zone_id" {
  value       = cloudflare_zone.this.id
  description = "The Cloudflare-generated Zone ID. Pass this to downstream modules (waf, load_balancer, ...)."
}

output "zone_name" {
  value       = cloudflare_zone.this.name
  description = "The zone apex domain name."
}

output "account_id" {
  value       = var.account_id
  description = "The Cloudflare Account ID owning the zone (convenience passthrough for account-scoped modules)."
}

output "name_servers" {
  value       = cloudflare_zone.this.name_servers
  description = "Cloudflare-assigned authoritative name servers. Set these at your registrar to activate the zone."
}

output "status" {
  value       = cloudflare_zone.this.status
  description = "Zone activation status (e.g. active, pending)."
}

output "dnssec" {
  value = var.dnssec ? {
    status           = cloudflare_zone_dnssec.this[0].status
    ds               = cloudflare_zone_dnssec.this[0].ds
    key_tag          = cloudflare_zone_dnssec.this[0].key_tag
    algorithm        = cloudflare_zone_dnssec.this[0].algorithm
    digest_type      = cloudflare_zone_dnssec.this[0].digest_type
    digest_algorithm = cloudflare_zone_dnssec.this[0].digest_algorithm
    digest           = cloudflare_zone_dnssec.this[0].digest
    flags            = cloudflare_zone_dnssec.this[0].flags
    public_key       = cloudflare_zone_dnssec.this[0].public_key
  } : null
  description = "DS record details to publish at the registrar, or null when DNSSEC is not managed. Registrars ask for either the full `ds` string or its parts (key tag, algorithm, digest type, digest); some want the DNSKEY (`flags`, `algorithm`, `public_key`) instead. All of it is public by design."
}

output "dns_record_ids" {
  value       = { for key, record in cloudflare_dns_record.this : key => record.id }
  description = "Map of internal DNS record keys to their Cloudflare record IDs."
}
