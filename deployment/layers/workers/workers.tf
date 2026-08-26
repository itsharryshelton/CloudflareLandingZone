# Workers and Workers KV: one namespace per kv_namespaces entry, one Worker per
# worker_scripts entry, with its bindings, routes, custom domains and cron
# triggers.
#
# Namespaces are declared first and referenced by key, so a binding is written as
# `kv_namespace_key = "config"` and Terraform works out the ordering. Nothing
# in an account tree ever carries a namespace ID.
#
# Downstream deployments pin an immutable tag instead of the local path - review root readme.md for more info:
#   source = "git::https://github.com/yourorg/CloudflareLandingZone//modules/workers_kv_namespace?ref=v1.0.0"
module "kv_namespaces" {
  source = "../../../modules/workers_kv_namespace"

  for_each = local.kv_namespaces

  # KV namespaces are account-scoped. No zone is involved at all.
  account_id = var.cloudflare_account_id

  title = each.value.title
  pairs = each.value.pairs

  # A ceiling on what Terraform will own, not on what the namespace may hold.
  # Bulk data is loaded from the pipeline against the namespace_id below.
  max_managed_pairs = each.value.max_managed_pairs
}

module "worker_scripts" {
  source = "../../../modules/worker_script"

  for_each = local.worker_scripts

  account_id  = var.cloudflare_account_id
  script_name = each.value.name

  # Source is passed by path, never inline: the file's contents stay out of
  # state, and content_sha256 is what makes an edit visible to a plan.
  content_file   = each.value.content_file
  content_sha256 = each.value.content_sha256
  main_module    = each.value.main_module
  body_part      = each.value.body_part

  compatibility_date  = each.value.compatibility_date
  compatibility_flags = each.value.compatibility_flags
  usage_model         = each.value.usage_model
  placement_mode      = each.value.placement_mode
  limits              = each.value.limits
  logpush             = each.value.logpush
  observability       = each.value.observability
  tail_consumers      = each.value.tail_consumers

  # kv_namespace_key -> namespace ID and worker_key -> Worker name are resolved
  # in locals.tf; everything else is passed through as written.
  bindings = each.value.bindings

  # zone_key -> zone ID, resolved by name in zone_lookup.tf.
  routes         = each.value.routes
  custom_domains = each.value.custom_domains

  cron_schedules = each.value.cron_schedules
}
