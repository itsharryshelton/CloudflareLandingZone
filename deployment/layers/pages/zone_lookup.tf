# Zone key -> zone ID, without reading the zones layer's state.
#
# Only zones named by a custom domain's zone_key are read. A deployment of
# projects served only on pages.dev looks nothing up.
data "cloudflare_zone" "this" {
  for_each = local.referenced_zones

  filter = {
    name = each.value.domain_name
    account = {
      id = var.cloudflare_account_id
    }
  }
}
