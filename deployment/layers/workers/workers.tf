# Workers and the state behind them: one namespace per kv_namespaces entry, one
# database per d1_databases entry, one queue per queues entry, and one Worker per
# worker_scripts entry with its bindings, routes, custom domains and cron
# triggers.
#
# Storage is declared first and referenced by key, so a binding is written as
# `kv_namespace_key = "config"` and Terraform works out the ordering. Nothing in
# an account tree ever carries a namespace ID, a database UUID or a queue ID.
#
# Ordering around queues is worth knowing about, because it is a loop that only
# stays open by being written this way. A queue must exist before a Worker can be
# given a binding that writes to it, and the Worker must exist before it can be
# named as that queue's consumer - so the chain is queue, Worker, consumer.
#
# That is three module calls, not two. `module.queues[binding.queue_key]` has a
# key only known at evaluation, so Terraform makes it depend on everything inside
# module.queues, not just queue_name. A consumer attached inside module.queues
# would therefore make every Worker wait on a consumer that is waiting on a
# Worker - a cycle, reported at validate.
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

module "d1_databases" {
  source                = "../../../modules/d1_database"
  for_each              = local.d1_databases
  account_id            = var.cloudflare_account_id
  name                  = each.value.name
  jurisdiction          = each.value.jurisdiction
  primary_location_hint = each.value.primary_location_hint
  read_replication_mode = each.value.read_replication_mode
}

module "queues" {
  source = "../../../modules/queue"

  for_each = local.queues

  account_id = var.cloudflare_account_id

  queue_name = each.value.name
  settings   = each.value.settings

  # No consumer here: it is attached by module.queue_consumers, below.
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

  # kv_namespace_key -> namespace ID, d1_database_key -> database UUID,
  # queue_key -> queue name and worker_key -> Worker name are resolved in
  # locals.tf; everything else is passed through as written.
  bindings = each.value.bindings

  # zone_key -> zone ID, resolved by name in zone_lookup.tf.
  routes         = each.value.routes
  custom_domains = each.value.custom_domains

  cron_schedules = each.value.cron_schedules
}

module "queue_consumers" {
  source = "../../../modules/queue_consumer"

  for_each = local.queue_consumers

  account_id = var.cloudflare_account_id

  # Read from the queue module rather than the variable, so the queue is created
  # before anything is attached to it.
  queue_id   = module.queues[each.key].queue_id
  queue_name = module.queues[each.key].queue_name

  # worker_key -> deployed Worker name and dead_letter_queue_key -> queue name
  # are resolved in locals.tf.
  type              = each.value.type
  script_name       = each.value.script_name
  dead_letter_queue = each.value.dead_letter_queue
  settings          = each.value.settings
}
