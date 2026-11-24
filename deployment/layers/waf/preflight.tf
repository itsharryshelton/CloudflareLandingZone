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
      error_message = "Unknown baseline rule name in ${join("; ", local.waf_unknown_baseline_rules)}. Available custom rules: ${join(", ", keys(local.waf_baseline_custom_rules))}. Available rate limits: ${join(", ", keys(local.waf_baseline_rate_limits))}. Available managed rulesets: ${join(", ", keys(local.waf_baseline_managed_rulesets))}. Available managed exceptions: ${join(", ", keys(local.waf_baseline_managed_exceptions))}."
    }

    precondition {
      condition     = length(local.waf_idle_managed_exceptions) == 0
      error_message = "A baseline managed exception has nothing to skip: ${join("; ", local.waf_idle_managed_exceptions)}. An exception only skips managed rulesets its own policy executes, and this policy executes none of the ones it targets - or, for html_submission without owasp_core, waf_html_submission_skip_rule_ids is empty. Add the managed ruleset to the policy or drop the exception."
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
      condition     = length(local.underpowered_baseline_rules) == 0
      error_message = "A baseline custom rule is selected on a zone below the plan that exposes the field it reads: ${join("; ", local.underpowered_baseline_rules)}. Cloudflare rejects the whole custom ruleset in that case, taking every other rule on the zone with it. Set the zone's real zone_tier in zones.tfvars or drop the rule from that policy."
    }

    precondition {
      condition     = length(local.account_waf_unknown_baselines) == 0
      error_message = "Unknown account-level baseline name in ${join("; ", local.account_waf_unknown_baselines)}. Available custom rules: ${join(", ", keys(local.waf_baseline_custom_rules))}. Available managed rulesets: ${join(", ", keys(local.waf_baseline_managed_rulesets))}."
    }

    precondition {
      condition     = length(local.account_waf_dangling_zone_keys) == 0
      error_message = "account_waf.zone_keys names keys that are not in var.zones: ${join(", ", local.account_waf_dangling_zone_keys)}. Valid keys: ${join(", ", keys(var.zones))}."
    }

    precondition {
      condition     = length(local.account_waf_non_enterprise_zones) == 0
      error_message = "account_waf.zone_keys names zones that are not Enterprise: ${join("; ", local.account_waf_non_enterprise_zones)}. Cloudflare only runs account-level WAF rules on Enterprise zones, so these would be listed as covered while getting nothing. Cover them with a zone policy in waf_policies instead, or correct their zone_tier in zones.tfvars."
    }

    precondition {
      condition     = length(local.underpowered_bot_traffic) == 0
      error_message = "bot_traffic is configured on a zone below bot_traffic_min_tier (\"${var.bot_traffic_min_tier}\"): ${join("; ", local.underpowered_bot_traffic)}. Verified bot categories are a Bot Management field, and Cloudflare rejects the entire ruleset when the zone is not entitled to it - which would take the baseline and tenant rules down with the bot rules. Either set the zone's real zone_tier in zones.tfvars, drop bot_traffic for that policy, or lower bot_traffic_min_tier if your account's entitlement genuinely differs."
    }
  }
}

# Checks rather than preconditions: both are legitimate states, just easy to
# reach by mistake.
check "account_waf_content_ignored_while_disabled" {
  assert {
    condition     = !local.account_waf_ignored_content
    error_message = "account_waf sets zone_keys, custom_rules, managed_rulesets or managed_exceptions, but account_waf_enabled is false, so none of it is deployed. Set account_waf_enabled = true once the account's account-level WAF entitlement is confirmed."
  }
}

check "account_waf_managed_rulesets_run_twice" {
  assert {
    condition     = length(local.account_waf_double_executed) == 0
    error_message = "These zone policies execute a managed ruleset the account level already runs on the same Enterprise zone: ${join("; ", local.account_waf_double_executed)}. Every request is evaluated by both copies, and the zone's own managed exceptions do not reach the account-level copy. Drop the ruleset from the zone policy, or narrow account_waf.zone_keys."
  }
}
