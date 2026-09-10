# Zone key -> zone ID, without reading the zones layer's state.
#
# Only zones a public hostname actually names are read. A deployment of
# private-network tunnels looks nothing up at all.
data "cloudflare_zone" "this" {
  for_each = local.referenced_zones

  filter = {
    name = each.value.domain_name
    account = {
      id = var.cloudflare_account_id
    }
  }
}
