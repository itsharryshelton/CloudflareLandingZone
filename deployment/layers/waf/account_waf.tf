# Account-level custom and managed WAF rulesets, enforced on Enterprise zones.
#
# Gated by var.account_waf_enabled because account-level WAF is an entitlement
# not every Enterprise account has, and Cloudflare only rejects it at apply.
# Rule content comes from the same catalogue as the zone policies
# (locals.waf.tf), so a baseline rule means the same thing at both levels.
#
# The account entry points are singletons: this layer is the only one that may
# declare them for http_request_firewall_custom and http_request_firewall_managed.
#
# Downstream deployments pin an immutable tag instead of the local path:
#   source = "git::https://github.com/Your-Org/cloudflare-platform-modules//account_waf?ref=v1.0.0"
module "account_waf" {
  source = "git::https://github.com/Your-Org/cloudflare-platform-modules//account_waf?ref=v1.0.0"

  count = var.account_waf_enabled ? 1 : 0

  account_id = var.cloudflare_account_id

  # Empty means every Enterprise zone in the account, managed here or not
  zone_names = local.account_waf_zone_names

  custom_rules       = local.account_waf_custom_rules
  managed_rulesets   = local.account_waf_managed_rulesets
  managed_exceptions = var.account_waf.managed_exceptions

  custom_ruleset_name     = coalesce(var.account_waf.custom_ruleset_name, "Account WAF - Custom Rules")
  custom_entrypoint_name  = coalesce(var.account_waf.custom_entrypoint_name, "Account WAF - Custom Rules Entry Point")
  managed_entrypoint_name = coalesce(var.account_waf.managed_entrypoint_name, "Account WAF - Managed Rules Entry Point")
}
