resource "terraform_data" "preflight" {
  input = { zones = length(var.zones) }

  lifecycle {
    precondition {
      condition     = length(local.orphaned_zone_config_keys) == 0
      error_message = "zone_config has entries with no matching zone in var.zones: ${join(", ", local.orphaned_zone_config_keys)}. Valid zone keys: ${join(", ", keys(var.zones))}. Left unchecked those zones would deploy with no DNS records."
    }
  }
}

# A `check` rather than a precondition on purpose: managing a rate plan is a legitimate thing to want, so this must not fail the plan.
check "zone_subscriptions_change_billing" {
  assert {
    condition     = length(local.subscription_managed_zones) == 0
    error_message = "BILLING: this run manages the Cloudflare rate plan for ${length(local.subscription_managed_zones)} zone(s): ${join("; ", local.subscription_managed_zones)}. Applying moves each zone onto that plan - an upgrade is charged, and a downgrade immediately strips entitlements such as WAF rule allowances, rate limiting and Bot Management from a live zone. Confirm every zone_tier is correct before applying, and that the token carries Billing Write. Set manage_zone_subscriptions = false to leave plans alone."
  }
}
