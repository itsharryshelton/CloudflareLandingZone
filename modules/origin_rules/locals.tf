# Operator-facing rules -> the shape cloudflare_ruleset wants.
#
# Same key set on every element, nulls included

locals {
  rules = [
    for rule in var.rules : {
      action      = "route"
      expression  = rule.expression
      description = coalesce(rule.description, rule.name)
      enabled     = rule.enabled

      action_parameters = {
        host_header = rule.host_header
        origin      = rule.origin
        sni         = rule.sni
      }
    }
  ]

  rule_labels = [for rule in local.rules : rule.description]

  # An SNI override without an origin override is nearly always a mistake: it
  # changes the handshake for the origin the DNS record already pointed at, which
  # is the one whose certificate presumably already matched.
  sni_without_origin = [
    for rule in var.rules : rule.name
    if rule.sni != null && rule.origin == null
  ]
}
