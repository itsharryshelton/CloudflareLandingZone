# Zone key -> zone ID, without reading the zones layer's state.
#
# Only zones named by a bucket's custom domain are read. A deployment whose buckets are all private looks nothing up, and can therefore be planned without credentials.

data "cloudflare_zone" "this" {
  for_each = local.referenced_zones

  filter = {
    name = each.value.domain_name
    account = {
      id = var.cloudflare_account_id
    }
  }
}
