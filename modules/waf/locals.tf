locals {
  # -------------------------------------------------------------------------
  # Bot traffic (http_request_firewall_custom, evaluated before everything else)
  # -------------------------------------------------------------------------

  # Cloudflare's AI bot taxonomy names three behaviours - Search, Agent and
  # Training - but the ruleset field exposes verified bot *categories*, which is
  # a longer and older list. This is the mapping between the two.
  #
  # "AI Search" is retained by Cloudflare only for backward compatibility: new
  # search crawlers, AI or otherwise, are classified as Search Engine Crawler.
  # Both are matched so a rule written today keeps covering bots classified
  # before the taxonomy changed.
  #
  # Search Engine Optimization is deliberately NOT part of search: an SEO
  # auditor analyses a site to rank it, it does not index content to answer
  # questions about it later, and lumping the two together means an allow rule
  # for Google also admits every SEO scraper.
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
        ? { ruleset = "current" }
        : null
      )

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

      # Present but null so every element of the ruleset's `rules` list has the
      # same attributes; the bot traffic rules above need it for skip.
      action_parameters = null
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

  custom_rule_labels     = [for rule in local.all_custom_rules : rule.description]
  rate_limit_rule_labels = [for rule in var.rate_limiting_rules : rule.name]
}
