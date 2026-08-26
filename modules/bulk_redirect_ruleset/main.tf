# The account's Bulk Redirect ruleset: one rule per list, in evaluation order.
# Expression construction lives in locals.tf.
#
# THIS RESOURCE IS A SINGLETON PER ACCOUNT
# Cloudflare allows exactly one entry-point ruleset per account per phase, and
# this is the one for http_request_redirect. Two Terraform states both declaring
# it will overwrite each other's rules on alternate applies, with no error from
# either - so the ruleset belongs in exactly one layer, and rules for every list
# in the account go through this one module instance.
#
# Bulk Redirects are evaluated early, before the request reaches the origin, and
# Cloudflare performs no further processing once a redirect has been executed.
# That is the whole appeal over doing the same job in a Worker: no invocation, no
# storage read, and a matched redirect never reaches anything downstream.

resource "cloudflare_ruleset" "this" {
  # A ruleset with no rules is not the same as no ruleset: it is an empty
  # entry point that Cloudflare keeps, and it makes "no Bulk Redirects here"
  # indistinguishable from "the rules were deleted".
  count = length(local.rules) > 0 ? 1 : 0

  account_id  = var.account_id
  name        = var.name
  kind        = "root"
  phase       = "http_request_redirect"
  description = var.description

  rules = local.rules
}
