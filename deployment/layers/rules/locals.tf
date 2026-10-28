locals {
  referenced_zones = {
    for key, zone in var.zones : key => zone
    if contains([for p in var.rule_policies : p.zone_key], key)
  }

  # One module instance per phase, but only for the policies that actually use
  # that phase - an empty ruleset is not created, so a policy that only sets
  # cache rules never appears in the transform or origin state at all.
  cache_policies = {
    for key, policy in var.rule_policies : key => policy
    if length(policy.cache_rules) > 0
  }

  transform_policies = {
    for key, policy in var.rule_policies : key => policy
    if length(policy.transform_rules) > 0
  }

  origin_policies = {
    for key, policy in var.rule_policies : key => policy
    if length(policy.origin_rules) > 0
  }

  redirect_policies = {
    for key, policy in var.rule_policies : key => policy
    if length(policy.redirect_rules) > 0
  }

  config_policies = {
    for key, policy in var.rule_policies : key => policy
    if length(policy.config_rules) > 0
  }

  # Only the zones that need one are enumerated: those with a phase whose
  # existing entry point imports.tf adopts.
  zones_with_adopted_phases = {
    for key, zone in var.zones : key => zone
    if contains(concat(
      [for p in local.redirect_policies : p.zone_key],
      [for p in local.config_policies : p.zone_key],
    ), key)
  }

  # Policy key => the ID of the zone's existing http_request_dynamic_redirect
  # entry point, or null where it has none. Drives the import in imports.tf.
  existing_redirect_entrypoints = {
    for key, policy in local.redirect_policies : key => one([
      for ruleset in data.cloudflare_rulesets.this[policy.zone_key].rulesets : ruleset.id
      if ruleset.phase == "http_request_dynamic_redirect" && ruleset.kind == "zone"
    ])
    if contains(keys(var.zones), policy.zone_key)
  }

  # The same for http_config_settings.
  existing_config_entrypoints = {
    for key, policy in local.config_policies : key => one([
      for ruleset in data.cloudflare_rulesets.this[policy.zone_key].rulesets : ruleset.id
      if ruleset.phase == "http_config_settings" && ruleset.kind == "zone"
    ])
    if contains(keys(var.zones), policy.zone_key)
  }

  # `acknowledge_public_response` is this layer's field, not Cloudflare's - see
  # the precondition below. Stripped here so the module keeps a schema that is
  # exactly the provider's.
  cache_rules_for_module = {
    for key, policy in local.cache_policies : key => [
      for rule in policy.cache_rules : {
        name        = rule.name
        expression  = rule.expression
        description = rule.description
        enabled     = rule.enabled

        cache       = rule.cache
        cache_key   = rule.cache_key
        edge_ttl    = rule.edge_ttl
        browser_ttl = rule.browser_ttl
        serve_stale = rule.serve_stale

        respect_strong_etags       = rule.respect_strong_etags
        origin_cache_control       = rule.origin_cache_control
        origin_error_page_passthru = rule.origin_error_page_passthru
        read_timeout               = rule.read_timeout
      }
    ]
  }

  # Likewise `acknowledge_unencrypted_origin`.
  config_rules_for_module = {
    for key, policy in local.config_policies : key => [
      for rule in policy.config_rules : {
        name        = rule.name
        expression  = rule.expression
        description = rule.description
        enabled     = rule.enabled

        ssl = rule.ssl
      }
    ]
  }

  # Preflight checks here
  dangling_zone_keys = [
    for key, policy in var.rule_policies : "rule_policies.${key}.zone_key = \"${policy.zone_key}\""
    if !contains(keys(var.zones), policy.zone_key)
  ]

  # A policy that names a zone and configures nothing. Legal, and silently does
  # nothing, which is the problem: it reads as coverage that is not there.
  empty_policies = [
    for key, policy in var.rule_policies : key
    if length(policy.cache_rules) == 0
    && length(policy.transform_rules) == 0
    && length(policy.origin_rules) == 0
    && length(policy.redirect_rules) == 0
    && length(policy.config_rules) == 0
  ]

  unguarded_cache_rules = flatten([
    for key, policy in var.rule_policies : [
      for rule in policy.cache_rules : "${key}: \"${rule.name}\""
      if rule.cache == true
      && rule.enabled
      && !rule.acknowledge_public_response
      && !strcontains(lower(rule.expression), "cookie")
      && !strcontains(lower(rule.expression), "authorization")
    ]
  ])

  # full still encrypts to the origin; flexible and off do not, and under
  # flexible the visitor's padlock looks the same as ever.
  unacknowledged_unencrypted_origins = flatten([
    for key, policy in var.rule_policies : [
      for rule in policy.config_rules : "${key}: \"${rule.name}\" (ssl = ${rule.ssl})"
      if contains(["flexible", "off"], coalesce(rule.ssl, "unset"))
      && rule.enabled
      && !rule.acknowledge_unencrypted_origin
    ]
  ])
}
