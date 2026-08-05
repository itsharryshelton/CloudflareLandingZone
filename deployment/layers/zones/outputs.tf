# Later layers resolve zones by name through data.cloudflare_zone rather than
# consuming these outputs, so the layers stay decoupled and can be applied
# independently. These exist for operators and pipeline reporting.

output "zones" {
  description = "Per-zone identifiers and activation state, keyed by zone key."
  value = {
    for key, zone in module.zones : key => {
      zone_id      = zone.zone_id
      zone_name    = zone.zone_name
      status       = zone.status
      name_servers = zone.name_servers
    }
  }
}

output "name_servers" {
  description = "Authoritative name servers per zone key. These must be set at the registrar before a zone leaves 'pending' - the usual reason an apply succeeds but the zone never activates, and why the waf and load_balancing layers can then fail to resolve it."
  value       = { for key, zone in module.zones : key => zone.name_servers }
}

output "dns_record_ids" {
  description = "Per-zone map of internal DNS record key (TYPE/fqdn/content) to Cloudflare record ID."
  value       = { for key, zone in module.zones : key => zone.dns_record_ids }
}
