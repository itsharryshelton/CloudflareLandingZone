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

output "dns_record_ids" {
  value       = { for key, record in cloudflare_dns_record.this : key => record.id }
  description = "Map of internal DNS record keys to their Cloudflare record IDs."
}
