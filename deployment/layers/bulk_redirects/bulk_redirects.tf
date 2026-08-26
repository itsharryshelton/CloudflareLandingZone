# Bulk Redirects: one list per bulk_redirect_lists entry, and the single
# account-level ruleset that switches them on.
#
# A list is inert until a rule names it, and a rule fails to apply if its list
# does not exist yet - so the ruleset depends on every list explicitly. Nothing in
# the rule's inputs references a list module output (the rule needs only the
# name, which comes from the variable), which is what lets preflight.tf assert on
# the whole configuration at plan time instead of deferring to apply.
#
# Downstream deployments pin an immutable tag instead of the local path - review root readme.md for more info:
#   source = "git::https://github.com/yourorg/CloudflareLandingZone//modules/bulk_redirect_list?ref=v1.0.0"
module "bulk_redirect_lists" {
  source = "../../../modules/bulk_redirect_list"

  for_each = local.bulk_redirect_lists

  # Bulk Redirect Lists are account-scoped. Each row carries its own hostname, so
  # no zone is involved anywhere in this layer.
  account_id = var.cloudflare_account_id

  name        = each.value.name
  description = each.value.description

  # False by default: Terraform owns the container, the pipeline loads the rows.
  # True means Cloudflare replaces the whole list on every apply.
  manage_items      = each.value.manage_items
  items             = each.value.items
  max_managed_items = each.value.max_managed_items
}

module "bulk_redirect_ruleset" {
  source = "../../../modules/bulk_redirect_ruleset"

  account_id = var.cloudflare_account_id
  name       = var.ruleset_name

  # Ordered. Cloudflare stops at the first rule that redirects.
  rules = local.bulk_redirect_rules

  # A rule naming a list that does not exist yet is rejected at apply time.
  depends_on = [module.bulk_redirect_lists]
}
