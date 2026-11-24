# Zone key -> zone ID, without reading the zones layer's state.
data "cloudflare_zone" "this" {
  for_each = local.managed_zones

  filter = {
    name = var.zones[each.key].domain_name
    account = {
      id = var.cloudflare_account_id
    }
  }
}
