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

  # Phase => ID of the account's existing root ruleset, or null where it has
  # none or account-level WAF is off. For the account imports in imports.tf.
  existing_account_entrypoints = {
    for phase in ["http_request_firewall_custom", "http_request_firewall_managed"] : phase => (
      var.account_waf_enabled
      ? one([
        for ruleset in data.cloudflare_rulesets.account[0].rulesets : ruleset.id
        if ruleset.phase == phase && ruleset.kind == "root"
      ])
      : null
    )
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
      managed_exceptions = concat(
        [
          for name, scope in policy.baseline_managed_exceptions : {
            name = local.waf_baseline_managed_exceptions[name].name
            expression = format(
              "http.host in {%s} and (%s)",
              join(" ", [for host in scope.hostnames : "\"${host}\""]),
              local.waf_baseline_managed_exceptions[name].expression,
            )
            # Every use of an exception switches protection off, so it is logged
            # rather than left to Cloudflare's default.
            logging = true
            skip    = { rules = local.waf_baseline_exception_targets[key][name] }
          }
          # Held back when there is nothing to skip, so the preflight reports why
          # instead of the module's generic empty-skip validation.
          if length(local.waf_baseline_exception_targets[key][name]) > 0
        ],
        policy.managed_exceptions,
      )
    })
  }

  # Policy key => IDs of the managed rulesets it executes
  waf_policy_managed_ruleset_ids = {
    for key, policy in var.waf_policies : key => concat(
      [for name in policy.baseline_managed_rulesets : local.waf_baseline_managed_rulesets[name].id],
      [for ruleset in policy.managed_rulesets : ruleset.id],
    )
  }

  # Policy key => baseline exception name => what it skips, narrowed to the
  # rulesets that policy executes. The module rejects an exception naming any
  # other, since it could never match.
  waf_baseline_exception_targets = {
    for key, policy in var.waf_policies : key => {
      for name in keys(policy.baseline_managed_exceptions) : name => {
        for ruleset_id, rule_ids in local.waf_baseline_managed_exceptions[name].rules : ruleset_id => rule_ids
        if length(rule_ids) > 0 && contains(local.waf_policy_managed_ruleset_ids[key], ruleset_id)
      }
      if contains(keys(local.waf_baseline_managed_exceptions), name)
    }
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
      [
        for name in keys(policy.baseline_managed_exceptions) : "${key}.baseline_managed_exceptions[\"${name}\"]"
        if !contains(keys(local.waf_baseline_managed_exceptions), name)
      ],
    )
  ])

  # A baseline exception selected on a policy that executes none of the rulesets
  # it skips - an empty skip, which Cloudflare rejects.
  waf_idle_managed_exceptions = flatten([
    for key, targets in local.waf_baseline_exception_targets : [
      for name, rules in targets : "${key} selects \"${name}\"" if length(rules) == 0
    ]
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
  waf_unsatisfied_baseline_rules = concat(
    flatten([
      for key, policy in var.waf_policies : [
        for name in concat(policy.baseline_custom_rules, keys(policy.baseline_managed_exceptions)) :
        "${key} selects \"${name}\": ${local.waf_baseline_requirements[name].reason}"
        if contains(keys(local.waf_baseline_requirements), name)
        && !local.waf_baseline_requirements[name].satisfied
      ]
    ]),
    [
      for name in local.account_waf_selected_custom_rules :
      "account_waf_baseline_custom_rules selects \"${name}\": ${local.waf_baseline_requirements[name].reason}"
      if contains(keys(local.waf_baseline_requirements), name)
      && !local.waf_baseline_requirements[name].satisfied
    ],
  )

  # Baseline rules selected on a zone below the plan that exposes their fields
  underpowered_baseline_rules = flatten([
    for key, policy in var.waf_policies : [
      for name in policy.baseline_custom_rules :
      "${key} selects \"${name}\" (needs ${local.waf_baseline_min_tier[name]}, zone \"${policy.zone_key}\" is ${local.zone_tiers[policy.zone_key]})"
      if contains(keys(local.waf_baseline_min_tier), name)
      && contains(keys(var.zones), policy.zone_key)
      && local.tier_rank[local.zone_tiers[policy.zone_key]] < local.tier_rank[local.waf_baseline_min_tier[name]]
    ]
  ])

  # -------------------------------------------------------------------------
  # Account-level WAF (account_waf.tf)
  # -------------------------------------------------------------------------
  # Nothing account-level is evaluated while the toggle is off, so a platform
  # selection in defaults.auto.tfvars cannot fail an account that lacks the
  # entitlement.
  account_waf_selected_custom_rules     = var.account_waf_enabled ? var.account_waf_baseline_custom_rules : []
  account_waf_selected_managed_rulesets = var.account_waf_enabled ? var.account_waf_baseline_managed_rulesets : []

  # Unknown names are dropped here and reported by the preflight, rather than
  # failing as a generic "Invalid index".
  account_waf_custom_rules = concat(
    [
      for name in local.account_waf_selected_custom_rules : local.waf_baseline_custom_rules[name]
      if contains(keys(local.waf_baseline_custom_rules), name)
    ],
    var.account_waf.custom_rules,
  )

  account_waf_managed_rulesets = concat(
    [
      for name in local.account_waf_selected_managed_rulesets : local.waf_baseline_managed_rulesets[name]
      if contains(keys(local.waf_baseline_managed_rulesets), name)
    ],
    var.account_waf.managed_rulesets,
  )

  account_waf_managed_ruleset_ids = [for ruleset in local.account_waf_managed_rulesets : ruleset.id]

  account_waf_zone_names = [
    for key in var.account_waf.zone_keys : var.zones[key].domain_name
    if contains(keys(var.zones), key)
  ]

  account_waf_unknown_baselines = concat(
    [
      for name in local.account_waf_selected_custom_rules : "account_waf_baseline_custom_rules[\"${name}\"]"
      if !contains(keys(local.waf_baseline_custom_rules), name)
    ],
    [
      for name in local.account_waf_selected_managed_rulesets : "account_waf_baseline_managed_rulesets[\"${name}\"]"
      if !contains(keys(local.waf_baseline_managed_rulesets), name)
    ],
  )

  account_waf_dangling_zone_keys = [
    for key in var.account_waf.zone_keys : key
    if var.account_waf_enabled && !contains(keys(var.zones), key)
  ]

  # A listed zone that is not Enterprise would match nothing while reading as
  # if it were covered.
  account_waf_non_enterprise_zones = [
    for key in var.account_waf.zone_keys : "${key} (tier \"${local.zone_tiers[key]}\")"
    if var.account_waf_enabled
    && contains(keys(var.zones), key)
    && local.tier_rank[local.zone_tiers[key]] < local.tier_rank["enterprise"]
  ]

  # Tenant account-level content written while the toggle is off. Baselines are
  # excluded: the platform selection is always set in defaults.auto.tfvars.
  account_waf_ignored_content = !var.account_waf_enabled && anytrue([
    length(var.account_waf.zone_keys) > 0,
    length(var.account_waf.custom_rules) > 0,
    length(var.account_waf.managed_rulesets) > 0,
    length(var.account_waf.managed_exceptions) > 0,
  ])

  # Zone policies that execute a managed ruleset the account level already runs
  # on the same zone. Only managed Enterprise zones in scope are known here; an
  # unmanaged zone cannot have a policy.
  account_waf_double_executed = flatten([
    for key, policy in var.waf_policies : [
      for id in setintersection(local.waf_policy_managed_ruleset_ids[key], local.account_waf_managed_ruleset_ids) :
      "${key} (zone \"${policy.zone_key}\") executes ${id}"
    ]
    if var.account_waf_enabled
    && contains(keys(var.zones), policy.zone_key)
    && local.tier_rank[local.zone_tiers[policy.zone_key]] >= local.tier_rank["enterprise"]
    && (length(var.account_waf.zone_keys) == 0 || contains(var.account_waf.zone_keys, policy.zone_key))
  ])
}
