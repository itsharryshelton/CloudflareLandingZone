# Zone key -> zone ID, without reading the zones layer's state.
#
# Only zones a policy actually names in zone_keys are read. An account whose
# policies are all account-wide looks nothing up at all.
data "cloudflare_zone" "this" {
  for_each = local.referenced_zones

  filter = {
    name = each.value.domain_name
    account = {
      id = var.cloudflare_account_id
    }
  }
}
