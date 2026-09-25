locals {
  skip_parameter_shape = {
    ruleset  = null
    rulesets = null
    phases   = null
    products = null
  }

  # -------------------------------------------------------------------------
  # Bot traffic (http_request_firewall_custom, evaluated before everything else)
  # -------------------------------------------------------------------------
  bot_traffic_default_categories = {
    search   = ["Search Engine Crawler", "AI Search"]
    agent    = ["AI Assistant"]
    training = ["AI Crawler"]
  }

  # Fixed evaluation order. Rules are positional in a ruleset, and iterating a
  # map would order them lexically (agent, search, training), which is not the
  # order an operator reading the dashboard expects.
  bot_traffic_behaviours = ["search", "agent", "training"]

  bot_traffic_selected = {
    search   = try(var.bot_traffic.search, null)
    agent    = try(var.bot_traffic.agent, null)
    training = try(var.bot_traffic.training, null)
  }

  bot_traffic_categories = {
    for behaviour, defaults in local.bot_traffic_default_categories :
    behaviour => try(var.bot_traffic.category_overrides[behaviour], null) == null
    ? defaults
    : var.bot_traffic.category_overrides[behaviour]
  }

  bot_traffic_active = [
    for behaviour in local.bot_traffic_behaviours : behaviour
    if local.bot_traffic_selected[behaviour] != null
  ]

  bot_traffic_rules = [
    for behaviour in local.bot_traffic_active : {
      # "allow" is not a firewall action. Letting a bot through means skipping
      # the rest of this ruleset, which is what makes ordering matter: an allow
      # for search only means anything because it is evaluated before the
      # tenant's own block rules.
      action = local.bot_traffic_selected[behaviour] == "allow" ? "skip" : local.bot_traffic_selected[behaviour]

      action_parameters = (
        local.bot_traffic_selected[behaviour] == "allow"
        ? merge(local.skip_parameter_shape, { ruleset = "current" })
        : null
      )

      logging = null

      expression = format(
        "(cf.verified_bot_category in {%s})",
        join(" ", [for category in local.bot_traffic_categories[behaviour] : "\"${category}\""]),
      )

      description = "Bot traffic - ${behaviour} (${local.bot_traffic_selected[behaviour]})"
      enabled     = try(var.bot_traffic.enabled, true)
    }
  ]

  # An override that resolves to an empty list would emit `in {}`, which
  # Cloudflare rejects as a syntax error rather than as an empty match.
  bot_traffic_empty_categories = [
    for behaviour in local.bot_traffic_active : behaviour
    if length(local.bot_traffic_categories[behaviour]) == 0
  ]

  # -------------------------------------------------------------------------
  # http_request_firewall_custom
  # -------------------------------------------------------------------------
  custom_rules = [
    for rule in var.custom_block_rules : {
      action      = rule.action
      expression  = rule.expression
      description = coalesce(rule.description, rule.name)
      enabled     = rule.enabled

      # Null on every action but skip
      action_parameters = (
        rule.action == "skip"
        ? merge(local.skip_parameter_shape, {
          ruleset  = try(rule.skip.ruleset, null)
          rulesets = try(rule.skip.rulesets, null)
          phases   = try(rule.skip.phases, null)
          products = try(rule.skip.products, null)
        })
        : null
      )

      # Cloudflare does not log a skip by default, so an exception is invisible
      logging = rule.logging == null ? null : { enabled = rule.logging }
    }
  ]

  # Bot traffic first, then baseline and tenant rules. See the note on the skip
  # action above - reversing this would mean a bot allow could never take effect.
  all_custom_rules = concat(local.bot_traffic_rules, local.custom_rules)

  # -------------------------------------------------------------------------
  # http_ratelimit
  # -------------------------------------------------------------------------
  rate_limit_rules = [
    for rule in var.rate_limiting_rules : {
      action      = rule.mitigation_action
      expression  = rule.expression
      description = rule.name
      enabled     = rule.enabled
      ratelimit = {
        characteristics     = rule.characteristics
        period              = rule.period
        requests_per_period = rule.requests
        counting_expression = rule.counting_expression
        requests_to_origin  = rule.requests_to_origin

        # Cloudflare requires mitigation_timeout = 0 when the mitigation action is "log"
        mitigation_timeout = (
          rule.mitigation_action == "log"
          ? 0
          : coalesce(rule.mitigation_timeout, rule.period)
        )
      }
    }
  ]

  # -------------------------------------------------------------------------
  # http_request_firewall_managed
  # -------------------------------------------------------------------------
  # Exceptions and execute rules share this entry point's `rules` list, so both
  # carry every action parameter either one uses: elements with different key
  # sets cannot be typed as one list.
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

  # Cloudflare's own rulesets are executed rather than declared
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
      expression  = ruleset.expression
      description = coalesce(ruleset.description, "Execute managed ruleset ${ruleset.id}")
      enabled     = ruleset.enabled
      logging     = null

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

  custom_rule_labels     = [for rule in local.all_custom_rules : rule.description]
  rate_limit_rule_labels = [for rule in var.rate_limiting_rules : rule.name]
  managed_rule_labels    = [for rule in local.all_managed_rules : rule.description]
}
