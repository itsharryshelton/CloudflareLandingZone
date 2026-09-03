# Zone key -> zone ID, without reading the zones layer's state.
data "cloudflare_zone" "this" {
  for_each = local.zones_with_records

  filter = {
    name = each.value.domain_name
    account = {
      id = var.cloudflare_account_id
    }
  }
}
