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
