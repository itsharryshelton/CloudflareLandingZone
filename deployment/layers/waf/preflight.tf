resource "terraform_data" "preflight" {
  input = {
    waf_policies     = length(var.waf_policies)
    referenced_zones = length(local.referenced_zones)
  }

  lifecycle {
    precondition {
      condition     = length(local.dangling_zone_keys) == 0
      error_message = "zone_key does not match any entry in var.zones: ${join("; ", local.dangling_zone_keys)}. Valid keys: ${join(", ", keys(var.zones))}. Both layers must be given the same accounts/<account>/zones.tfvars."
    }

    precondition {
      condition     = length(local.waf_unknown_baseline_rules) == 0
      error_message = "Unknown baseline rule name in ${join("; ", local.waf_unknown_baseline_rules)}. Available custom rules: ${join(", ", keys(local.waf_baseline_custom_rules))}. Available rate limits: ${join(", ", keys(local.waf_baseline_rate_limits))}. Available managed rulesets: ${join(", ", keys(local.waf_baseline_managed_rulesets))}."
    }

    precondition {
      condition     = length(local.underpowered_managed_rules) == 0
      error_message = "Managed rulesets are configured on a zone below managed_rules_min_tier (\"${var.managed_rules_min_tier}\"): ${join("; ", local.underpowered_managed_rules)}. The Cloudflare Managed Ruleset and the OWASP Core Ruleset both require Pro or above, and Cloudflare rejects the whole entry-point ruleset when the zone is not entitled to one it names - so the zone would end up with no managed rules rather than with the unentitled one missing. Either set the zone's real zone_tier in zones.tfvars, drop the managed rulesets for that policy, or lower managed_rules_min_tier if your account's entitlement genuinely differs."
    }

    precondition {
      condition     = length(local.waf_unsatisfied_baseline_rules) == 0
      error_message = "A baseline WAF rule was selected without the input it depends on: ${join("; ", local.waf_unsatisfied_baseline_rules)}"
    }

    precondition {
      condition     = length(local.underpowered_bot_traffic) == 0
      error_message = "bot_traffic is configured on a zone below bot_traffic_min_tier (\"${var.bot_traffic_min_tier}\"): ${join("; ", local.underpowered_bot_traffic)}. Verified bot categories are a Bot Management field, and Cloudflare rejects the entire ruleset when the zone is not entitled to it - which would take the baseline and tenant rules down with the bot rules. Either set the zone's real zone_tier in zones.tfvars, drop bot_traffic for that policy, or lower bot_traffic_min_tier if your account's entitlement genuinely differs."
    }
  }
}
