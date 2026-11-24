# Account-level WAF: one custom ruleset and the account's custom and managed
# entry points. Rule mapping and scope construction live in locals.tf.
#
# REQUIRES ACCOUNT-LEVEL WAF ENTITLEMENT
# Account-level WAF rulesets are an Enterprise feature, and not every
# Enterprise account is entitled to them. Without it the API rejects the
# rulesets at apply time - a plan cannot tell - so callers gate this module
# behind an explicit toggle.
#
# THE ENTRY POINTS ARE SINGLETONS PER ACCOUNT
# Cloudflare allows exactly one entry-point ruleset per account per phase. Two
# Terraform states both declaring one will overwrite each other's rules on
# alternate applies with no error from either, so call this module from one
# layer only.
#
# Account-level entry points are evaluated before the zone's own entry point in
# the same phase, and only on Enterprise zones: every execute rule here ends
# with `and cf.zone.plan eq "ENT"`, which the API requires.

# Custom rules cannot sit directly in an account entry point: they live in a
# ruleset of kind "custom" that the entry point executes.
resource "cloudflare_ruleset" "custom" {
  count = length(local.custom_rules) > 0 ? 1 : 0

  account_id  = var.account_id
  name        = var.custom_ruleset_name
  kind        = "custom"
  phase       = "http_request_firewall_custom"
  description = "Managed by Terraform (cloudflarelandingzone/modules/account_waf)."

  rules = local.custom_rules

  lifecycle {
    precondition {
      condition     = length(distinct(local.custom_rule_labels)) == length(local.custom_rule_labels)
      error_message = "Account custom rules must be uniquely labelled: two rules resolve to the same description, which makes them indistinguishable in the Cloudflare dashboard and in audit logs."
    }
  }
}

resource "cloudflare_ruleset" "custom_entrypoint" {
  count = length(local.custom_rules) > 0 ? 1 : 0

  account_id  = var.account_id
  name        = var.custom_entrypoint_name
  kind        = "root"
  phase       = "http_request_firewall_custom"
  description = "Managed by Terraform (cloudflarelandingzone/modules/account_waf)."

  rules = [
    {
      action      = "execute"
      expression  = local.custom_deploy_expression
      description = "Execute ${var.custom_ruleset_name}"
      enabled     = true
      action_parameters = {
        id = cloudflare_ruleset.custom[0].id
      }
    },
  ]
}

resource "cloudflare_ruleset" "managed_entrypoint" {
  count = length(local.managed_ruleset_rules) > 0 ? 1 : 0

  account_id  = var.account_id
  name        = var.managed_entrypoint_name
  kind        = "root"
  phase       = "http_request_firewall_managed"
  description = "Managed by Terraform (cloudflarelandingzone/modules/account_waf)."

  # Exceptions, then execute rules
  rules = local.all_managed_rules

  lifecycle {
    precondition {
      condition     = length(distinct(local.managed_rule_labels)) == length(local.managed_rule_labels)
      error_message = "Account managed rules must be uniquely described: two entries across managed_exceptions and managed_rulesets resolve to the same description."
    }
  }
}
