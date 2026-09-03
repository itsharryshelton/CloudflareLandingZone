locals {
  referenced_zones = {
    for key, zone in var.zones : key => zone
    if contains([for p in var.rule_policies : p.zone_key], key)
  }

  # One module instance per phase, but only for the policies that actually use it
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

  # `acknowledge_public_response` is this layer's field, not Cloudflare's
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

  # Preflight checks here
  dangling_zone_keys = [
    for key, policy in var.rule_policies : "rule_policies.${key}.zone_key = \"${policy.zone_key}\""
    if !contains(keys(var.zones), policy.zone_key)
  ]

  # A policy that names a zone and configures nothing
  empty_policies = [
    for key, policy in var.rule_policies : key
    if length(policy.cache_rules) == 0
    && length(policy.transform_rules) == 0
    && length(policy.origin_rules) == 0
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
}
