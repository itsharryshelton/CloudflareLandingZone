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
