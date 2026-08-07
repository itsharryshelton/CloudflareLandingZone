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

output "zone_rules" {
  description = "Per-zone tier, what that tier unlocks, and whether this layer owns the plan and the bot posture. `subscription_id` is null unless the rate plan is managed here."
  value = {
    for key, rules in module.zone_rules : key => {
      zone_tier              = rules.zone_tier
      tier_capabilities      = rules.tier_capabilities
      subscription_id        = rules.subscription_id
      subscription_state     = rules.subscription_state
      bot_management_managed = rules.bot_management_managed
      using_latest_bot_model = rules.using_latest_bot_model
    }
  }
}

output "zone_tiers" {
  description = "Zone key => rate plan. The waf layer gates bot traffic rules on the same value, taken from the same inventory file, so a mismatch here means the two layers were given different zones.tfvars."
  value       = { for key, zone in local.zones : key => zone.zone_tier }
}

output "dns_record_ids" {
  description = "Per-zone map of internal DNS record key (TYPE/fqdn/content) to Cloudflare record ID."
  value       = { for key, zone in module.zones : key => zone.dns_record_ids }
}
