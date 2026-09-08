locals {
  referenced_zones = {
    for key, zone in var.zones : key => zone
    if contains([for p in var.waf_policies : p.zone_key], key)
  }

  # Only the zones that need one are enumerated
  zones_with_managed_rulesets = {
    for key, zone in var.zones : key => zone
    if contains([
      for p in var.waf_policies :
      p.zone_key if length(p.baseline_managed_rulesets) > 0 || length(p.managed_rulesets) > 0
    ], key)
  }

  # Policy key => the ID of the zone's existing http_request_firewall_managed
  # entry point, or null where it has none. For the import in imports.tf.
  existing_managed_entrypoints = {
    for key, policy in var.waf_policies : key => one([
      for ruleset in data.cloudflare_rulesets.this[policy.zone_key].rulesets : ruleset.id
      if ruleset.phase == "http_request_firewall_managed" && ruleset.kind == "zone"
    ])
    if(length(policy.baseline_managed_rulesets) > 0 || length(policy.managed_rulesets) > 0)
    && contains(keys(var.zones), policy.zone_key)
  }

  # Baseline rules first, tenant rules after.
  waf_policies = {
    for key, policy in var.waf_policies : key => merge(policy, {
      custom_block_rules = concat(
        [for name in policy.baseline_custom_rules : local.waf_baseline_custom_rules[name]],
        policy.custom_block_rules,
      )
      # Cloudflare counts zone-level rate limits per colo, so it rejects any
      # characteristics set that omits cf.colo.id (API error 20155). Added here
      # so neither the catalogue nor a tenant rule has to remember it.
      rate_limiting_rules = [
        for rule in concat(
          [for name in policy.baseline_rate_limits : local.waf_baseline_rate_limits[name]],
          policy.rate_limiting_rules,
          ) : merge(rule, {
            characteristics = distinct(concat(rule.characteristics, ["cf.colo.id"]))
        })
      ]
      managed_rulesets = concat(
        [for name in policy.baseline_managed_rulesets : local.waf_baseline_managed_rulesets[name]],
        policy.managed_rulesets,
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

  bot_traffic_min_rank   = local.tier_rank[var.bot_traffic_min_tier]
  managed_rules_min_rank = local.tier_rank[var.managed_rules_min_tier]

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
      [
        for name in policy.baseline_managed_rulesets : "${key}.baseline_managed_rulesets[\"${name}\"]"
        if !contains(keys(local.waf_baseline_managed_rulesets), name)
      ],
    )
  ])

  # Bot traffic asked for on a zone whose plan does not expose the verified bot
  # category field. Cloudflare rejects the whole ruleset in that case.
  underpowered_bot_traffic = [
    for key, policy in var.waf_policies :
    "${key} (zone \"${policy.zone_key}\", tier \"${local.zone_tiers[policy.zone_key]}\")"
    if policy.bot_traffic != null
    && contains(keys(var.zones), policy.zone_key)
    && local.tier_rank[local.zone_tiers[policy.zone_key]] < local.bot_traffic_min_rank
  ]

  # Managed rules asked for on a zone below the plan Cloudflare requires for them.
  underpowered_managed_rules = [
    for key, policy in var.waf_policies :
    "${key} (zone \"${policy.zone_key}\", tier \"${local.zone_tiers[policy.zone_key]}\")"
    if(length(policy.baseline_managed_rulesets) > 0 || length(policy.managed_rulesets) > 0)
    && contains(keys(var.zones), policy.zone_key)
    && local.tier_rank[local.zone_tiers[policy.zone_key]] < local.managed_rules_min_rank
  ]

  # Baseline rules selected while the variable they depend on is empty
  waf_unsatisfied_baseline_rules = flatten([
    for key, policy in var.waf_policies : [
      for name in policy.baseline_custom_rules :
      "${key} selects \"${name}\": ${local.waf_baseline_requirements[name].reason}"
      if contains(keys(local.waf_baseline_requirements), name)
      && !local.waf_baseline_requirements[name].satisfied
    ]
  ])
}
