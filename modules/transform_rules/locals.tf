# Operator-facing rules -> the shape cloudflare_ruleset wants.

locals {
  rules = [
    for rule in var.rules : {
      action      = "rewrite"
      expression  = rule.expression
      description = coalesce(rule.description, rule.name)
      enabled     = rule.enabled

      action_parameters = {
        headers = rule.headers
      }
    }
  ]

  rule_labels = [for rule in local.rules : rule.description]
}
