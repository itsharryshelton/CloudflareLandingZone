output "kv_namespaces" {
  description = <<-EOT
    Per-namespace identifiers, keyed by namespace key. `namespace_id` is what a
    bulk load step needs:

      wrangler kv bulk put ./data.json --namespace-id "$NAMESPACE_ID" --remote

    `managed_key_count` counts only the keys Terraform owns. Keys written by the
    application or by a bulk load are not counted and are not touched by an apply.
  EOT
  value = {
    for key, namespace in module.kv_namespaces : key => {
      namespace_id      = namespace.namespace_id
      title             = namespace.title
      managed_key_count = namespace.managed_key_count
    }
  }
}

output "d1_databases" {
  description = <<-EOT
    Per-database identifiers, keyed by database key. `database_id` is what a
    migration step needs:

      wrangler d1 migrations apply "$DATABASE_NAME" --remote

    `file_size` and `num_tables` are read at refresh rather than managed, and are
    here because D1's ceiling is 10 GB per database and nothing else in the
    pipeline reports the approach to it.
  EOT
  value = {
    for key, database in module.d1_databases : key => {
      database_id           = database.database_id
      name                  = database.name
      jurisdiction          = database.jurisdiction
      read_replication_mode = database.read_replication_mode
      file_size             = database.file_size
      num_tables            = database.num_tables
    }
  }
}

output "queues" {
  description = "Per-queue identifiers and wiring, keyed by queue key. `consumer_script_name` null means nothing is reading the queue, and `delivery_paused` true means producers are still writing into a backlog that is not moving. `producers_total_count` counts what Cloudflare sees bound to the queue, including Workers deployed outside this pipeline."
  value = {
    for key, queue in module.queues : key => {
      queue_id              = queue.queue_id
      queue_name            = queue.queue_name
      consumer_script_name  = try(module.queue_consumers[key].script_name, null)
      dead_letter_queue     = try(module.queue_consumers[key].dead_letter_queue, null)
      delivery_paused       = queue.delivery_paused
      producers_total_count = queue.producers_total_count
      consumers_total_count = queue.consumers_total_count
    }
  }
}

output "worker_scripts" {
  description = "Per-Worker identifiers and triggers, keyed by Worker key. `etag` is the hash of the deployed code, which is the quickest way to confirm a deploy landed. `inline_secret_binding_names` should be empty; anything in it is a secret held in this layer's state."
  value = {
    for key, script in module.worker_scripts : key => {
      name                        = script.script_name
      etag                        = script.etag
      has_modules                 = script.has_modules
      routes                      = script.routes
      custom_domains              = script.custom_domains
      cron_schedules              = script.cron_schedules
      inline_secret_binding_names = script.inline_secret_binding_names
    }
  }
}

output "resolved_zone_ids" {
  description = "Zone key => zone ID as resolved by name, for the zones a route or a custom domain references. Empty when no Worker has a trigger."
  value       = { for key, zone in data.cloudflare_zone.this : key => zone.id }
}
