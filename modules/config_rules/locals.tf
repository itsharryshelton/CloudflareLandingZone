# Operator-facing rules -> the shape cloudflare_ruleset wants.
#
# Same key set on every element, nulls included: a ruleset's `rules` is one list
# and Terraform must unify the type of every element in it. A setting added
# later gets a key in action_parameters here, set to null where a rule leaves
# it unset, so the API keeps the zone's own value for it.

locals {
  rules = [
    for rule in var.rules : {
      action      = "set_config"
      expression  = rule.expression
      description = coalesce(rule.description, rule.name)
      enabled     = rule.enabled

      action_parameters = {
        ssl = rule.ssl
      }
    }
  ]

  rule_labels = [for rule in local.rules : rule.description]
}
