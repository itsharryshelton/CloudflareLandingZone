locals {
  # -------------------------------------------------------------------------
  # Deployment scope
  # -------------------------------------------------------------------------
  # Cloudflare rejects an account-level execute rule whose expression does not
  # end with `and cf.zone.plan eq "ENT"`. "Every zone" is written as a
  # non-empty zone name rather than as `true`, so the required clause always
  # has something to be ANDed onto.
  zone_scope = (
    length(var.zone_names) == 0
    ? "(cf.zone.name ne \"\")"
    : format("(cf.zone.name in {%s})", join(" ", [for name in var.zone_names : "\"${name}\""]))
  )

  enterprise_clause = "cf.zone.plan eq \"ENT\""

  custom_deploy_expression = "${local.zone_scope} and ${local.enterprise_clause}"

  # -------------------------------------------------------------------------
  # Account custom ruleset (kind custom, http_request_firewall_custom)
  # -------------------------------------------------------------------------
  skip_parameter_shape = {
    ruleset = null
    phases  = null
  }

  custom_rules = [
    for rule in var.custom_rules : {
      action      = rule.action
      expression  = rule.expression
      description = coalesce(rule.description, rule.name)
      enabled     = rule.enabled

      action_parameters = (
        rule.action == "skip"
        ? merge(local.skip_parameter_shape, {
          ruleset = try(rule.skip.ruleset, null)
          phases  = try(rule.skip.phases, null)
        })
        : null
      )

      # Cloudflare does not log a skip by default, so an exception is invisible
      logging = rule.logging == null ? null : { enabled = rule.logging }
    }
  ]

  # -------------------------------------------------------------------------
  # Account managed entry point (kind root, http_request_firewall_managed)
  # -------------------------------------------------------------------------
  # Exceptions and execute rules share one `rules` list, so both carry every
  # action parameter either one uses: elements with different key sets cannot
  # be typed as one list.
  managed_parameter_shape = {
    id        = null
    version   = null
    overrides = null
    ruleset   = null
    rulesets  = null
    rules     = null
  }

  # A skip only affects the execute rules listed after it, so these go first.
  managed_exception_rules = [
    for exception in var.managed_exceptions : {
      action      = "skip"
      expression  = exception.expression
      description = coalesce(exception.description, exception.name)
      enabled     = exception.enabled

      action_parameters = merge(local.managed_parameter_shape, {
        ruleset  = exception.skip.ruleset
        rulesets = exception.skip.rulesets
        rules    = exception.skip.rules
      })

      logging = exception.logging == null ? null : { enabled = exception.logging }
    }
  ]

  managed_ruleset_overrides = [
    for ruleset in var.managed_rulesets :
    anytrue([
      try(ruleset.overrides.action, null) != null,
      try(ruleset.overrides.enabled, null) != null,
      try(ruleset.overrides.sensitivity_level, null) != null,
      length(try(ruleset.overrides.categories, [])) > 0,
      length(try(ruleset.overrides.rules, [])) > 0,
    ]) ? ruleset.overrides : null
  ]

  managed_ruleset_rules = [
    for index, ruleset in var.managed_rulesets : {
      action      = "execute"
      description = coalesce(ruleset.description, "Execute managed ruleset ${ruleset.id}")
      enabled     = ruleset.enabled
      logging     = null

      # "true" is dropped rather than wrapped: it adds nothing to the scope, and
      # the ENT clause must stay last.
      expression = join(" and ", compact([
        trimspace(ruleset.expression) == "true" ? "" : "(${ruleset.expression})",
        local.zone_scope,
        local.enterprise_clause,
      ]))

      action_parameters = merge(local.managed_parameter_shape, {
        id      = ruleset.id
        version = ruleset.version

        overrides = local.managed_ruleset_overrides[index] == null ? null : {
          action            = local.managed_ruleset_overrides[index].action
          enabled           = local.managed_ruleset_overrides[index].enabled
          sensitivity_level = local.managed_ruleset_overrides[index].sensitivity_level

          categories = length(local.managed_ruleset_overrides[index].categories) == 0 ? null : [
            for category in local.managed_ruleset_overrides[index].categories : {
              category          = category.category
              action            = category.action
              enabled           = category.enabled
              sensitivity_level = category.sensitivity_level
            }
          ]

          rules = length(local.managed_ruleset_overrides[index].rules) == 0 ? null : [
            for rule in local.managed_ruleset_overrides[index].rules : {
              id                = rule.id
              action            = rule.action
              enabled           = rule.enabled
              score_threshold   = rule.score_threshold
              sensitivity_level = rule.sensitivity_level
            }
          ]
        }
      })
    }
  ]

  all_managed_rules = concat(local.managed_exception_rules, local.managed_ruleset_rules)

  custom_rule_labels  = [for rule in local.custom_rules : rule.description]
  managed_rule_labels = [for rule in local.all_managed_rules : rule.description]
}
