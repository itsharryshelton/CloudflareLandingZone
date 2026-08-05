locals {
  # http_request_firewall_custom
  custom_rules = [
    for rule in var.custom_block_rules : {
      action      = rule.action
      expression  = rule.expression
      description = coalesce(rule.description, rule.name)
      enabled     = rule.enabled
    }
  ]

  # http_ratelimit
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

  custom_rule_labels     = [for rule in var.custom_block_rules : coalesce(rule.description, rule.name)]
  rate_limit_rule_labels = [for rule in var.rate_limiting_rules : rule.name]
}
