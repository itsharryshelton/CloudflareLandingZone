# Operator-facing rules -> the shape cloudflare_ruleset wants.
#
# target_url and target_url_expression are flattened onto one field each so a
# rule reads as one object. The provider nests them under from_value.target_url,
# and both keys are always present, null where unused, so every element of the
# list has the same type.

locals {
  rules = [
    for rule in var.rules : {
      action      = "redirect"
      expression  = rule.expression
      description = coalesce(rule.description, rule.name)
      enabled     = rule.enabled

      action_parameters = {
        from_value = {
          status_code           = rule.status_code
          preserve_query_string = rule.preserve_query_string
          target_url = {
            value      = rule.target_url
            expression = rule.target_url_expression
          }
        }
      }
    }
  ]

  rule_labels = [for rule in local.rules : rule.description]
}
