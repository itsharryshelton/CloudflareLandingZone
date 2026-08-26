# Zone key -> zone ID, without reading the zones layer's state.
#
# Only zones named by a Worker's route or custom domain are read. A deployment whose Workers have no triggers - a service binding target, or one deployed ahead of being wired up - looks nothing up, and can therefore be planned without credentials.

data "cloudflare_zone" "this" {
  for_each = local.referenced_zones

  filter = {
    name = each.value.domain_name
    account = {
      id = var.cloudflare_account_id
    }
  }
}
