locals {
  referenced_zones = {
    for key, zone in var.zones : key => zone
    if contains([for p in var.waf_policies : p.zone_key], key)
  }

  # Baseline rules first, tenant rules after.
  waf_policies = {
    for key, policy in var.waf_policies : key => merge(policy, {
      custom_block_rules = concat(
        [for name in policy.baseline_custom_rules : local.waf_baseline_custom_rules[name]],
        policy.custom_block_rules,
      )
      rate_limiting_rules = concat(
        [for name in policy.baseline_rate_limits : local.waf_baseline_rate_limits[name]],
        policy.rate_limiting_rules,
      )
    })
  }

  # Same ranking as ../../../modules/zone_rules/locals.tf. Duplicated rather than
  # shared because a layer cannot read another layer's locals
  tier_rank = {
    free                = 0
    partners_free       = 0
    lite                = 1
    pro                 = 2
    pro_plus            = 2
    partners_pro        = 2
    business            = 3
    partners_business   = 3
    enterprise          = 4
    partners_enterprise = 4
    partners_ent        = 4
  }

  zone_tiers = {
    for key, zone in var.zones : key => coalesce(zone.zone_tier, var.default_zone_tier)
  }

  bot_traffic_min_rank = local.tier_rank[var.bot_traffic_min_tier]

  # Preflight checks here
  dangling_zone_keys = [
    for key, policy in var.waf_policies : "waf_policies.${key}.zone_key = \"${policy.zone_key}\""
    if !contains(keys(var.zones), policy.zone_key)
  ]

  # A misspelt baseline name would otherwise surface as Terraform's generic
  # "Invalid index" against a local, which does not say which policy is at fault.
  waf_unknown_baseline_rules = flatten([
    for key, policy in var.waf_policies : concat(
      [
        for name in policy.baseline_custom_rules : "${key}.baseline_custom_rules[\"${name}\"]"
        if !contains(keys(local.waf_baseline_custom_rules), name)
      ],
      [
        for name in policy.baseline_rate_limits : "${key}.baseline_rate_limits[\"${name}\"]"
        if !contains(keys(local.waf_baseline_rate_limits), name)
      ],
    )
  ])

  # Bot traffic asked for on a zone whose plan does not expose the verified bot
  # category field. Cloudflare rejects the whole ruleset in that case, taking the
  # baseline and tenant rules down with it, so the zone ends up with no custom
  # firewall rules at all rather than with the bot rules missing.
  #
  # Evaluated only for policies whose zone_key resolves, so a dangling key
  # reports as a dangling key rather than as a tier problem.
  underpowered_bot_traffic = [
    for key, policy in var.waf_policies :
    "${key} (zone \"${policy.zone_key}\", tier \"${local.zone_tiers[policy.zone_key]}\")"
    if policy.bot_traffic != null
    && contains(keys(var.zones), policy.zone_key)
    && local.tier_rank[local.zone_tiers[policy.zone_key]] < local.bot_traffic_min_rank
  ]

  # Baseline rules selected while the variable they depend on is empty. See the
  # reasoning in locals.waf.tf - these are unsafe, not merely useless.
  waf_unsatisfied_baseline_rules = flatten([
    for key, policy in var.waf_policies : [
      for name in policy.baseline_custom_rules :
      "${key} selects \"${name}\": ${local.waf_baseline_requirements[name].reason}"
      if contains(keys(local.waf_baseline_requirements), name)
      && !local.waf_baseline_requirements[name].satisfied
    ]
  ])
}
