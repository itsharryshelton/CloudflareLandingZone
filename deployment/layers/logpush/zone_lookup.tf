# Zone key -> zone ID, without reading the zones layer's state.
#
# Only zones a zone-scoped job actually names are read. An account that pushes
# only account datasets looks nothing up at all.
data "cloudflare_zone" "this" {
  for_each = local.referenced_zones

  filter = {
    name = each.value.domain_name
    account = {
      id = var.cloudflare_account_id
    }
  }
}
