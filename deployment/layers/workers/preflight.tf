# Cross-variable checks. A module block cannot carry lifecycle.precondition and
# variable validation cannot compare two variables, so they live on a state-only
# resource from Terraform's built-in provider. No credentials, no API calls.
#
# Every condition here reads var.* or local.worker_baseline, never the resolved
# local.worker_scripts: that one carries module outputs, which are unknown until
# apply, and a precondition on an unknown value is deferred to apply - which is
# after the operator has stopped looking at the plan.

resource "terraform_data" "preflight" {
  input = {
    kv_namespaces    = length(var.kv_namespaces)
    d1_databases     = length(var.d1_databases)
    queues           = length(var.queues)
    worker_scripts   = length(var.worker_scripts)
    referenced_zones = length(local.referenced_zones)
  }

  lifecycle {
    precondition {
      condition     = length(local.dangling_zone_keys) == 0
      error_message = "zone_key does not match any entry in var.zones: ${join("; ", local.dangling_zone_keys)}. Valid keys: ${join(", ", keys(var.zones))}. Both layers must be given the same accounts/<account>/zones.tfvars."
    }

    precondition {
      condition     = length(local.dangling_kv_namespace_keys) == 0
      error_message = "A binding references a KV namespace that this layer does not declare: ${join("; ", local.dangling_kv_namespace_keys)}. Valid keys: ${join(", ", keys(var.kv_namespaces))}. A namespace created elsewhere can still be bound - pass its namespace_id directly instead."
    }

    precondition {
      condition     = length(local.dangling_worker_keys) == 0
      error_message = "A service binding references a Worker that this layer does not declare: ${join("; ", local.dangling_worker_keys)}. Valid keys: ${join(", ", keys(var.worker_scripts))}. For a Worker owned elsewhere, set service to its name instead of worker_key."
    }

    precondition {
      condition     = length(local.dangling_d1_database_keys) == 0
      error_message = "A binding references a D1 database that this layer does not declare: ${join("; ", local.dangling_d1_database_keys)}. Valid keys: ${join(", ", keys(var.d1_databases))}. A database created elsewhere can still be bound - pass its database_id directly instead."
    }

    precondition {
      condition     = length(local.dangling_queue_keys) == 0
      error_message = "A binding references a queue that this layer does not declare: ${join("; ", local.dangling_queue_keys)}. Valid keys: ${join(", ", keys(var.queues))}. A queue owned elsewhere can still be produced to - pass its queue_name directly instead."
    }

    precondition {
      condition     = length(local.dangling_queue_consumer_worker_keys) == 0
      error_message = "A queue consumer references a Worker that this layer does not declare: ${join("; ", local.dangling_queue_consumer_worker_keys)}. Valid keys: ${join(", ", keys(var.worker_scripts))}. For a Worker deployed elsewhere, set script_name to its name instead of worker_key - Cloudflare refuses a consumer naming a Worker that does not exist."
    }

    precondition {
      condition     = length(local.dangling_dead_letter_queue_keys) == 0
      error_message = "A queue consumer's dead letter queue names a queue this layer does not declare: ${join("; ", local.dangling_dead_letter_queue_keys)}. Valid keys: ${join(", ", keys(var.queues))}. For a queue owned elsewhere, set dead_letter_queue to its name instead."
    }

    precondition {
      condition     = length(local.self_dead_letter_queues) == 0
      error_message = "These queues are their own dead letter queue: ${join("; ", local.self_dead_letter_queues)}. A message that exhausts its retries would be written straight back to the queue it just failed on, which bills for every attempt and never drains. Point it at a separate queue."
    }

    precondition {
      condition     = length(local.queues_without_consumer) == 0
      error_message = "These queues have nothing reading them: ${join("; ", local.queues_without_consumer)}. Producers keep succeeding, the backlog grows, and each message is dropped when it reaches the retention period with nothing raising an error. Declare a consumer, or set allow_queues_without_consumer = true in layers/workers/defaults.auto.tfvars where the consumer genuinely lives outside this pipeline. A queue another queue dead letters into is already exempt."
    }

    precondition {
      condition     = length(local.consumers_without_dead_letter_queue) == 0
      error_message = "These queue consumers have no dead letter queue: ${join("; ", local.consumers_without_dead_letter_queue)}. A message that fails max_retries times is deleted, with no error and no copy to look at - the batch that broke the consumer is the one nobody can examine. Add dead_letter_queue_key pointing at another entry in var.queues, or set allow_queue_consumer_without_dead_letter_queue = true where the messages are genuinely disposable."
    }

    precondition {
      condition     = length(local.replicated_d1_in_jurisdiction) == 0
      error_message = "These D1 databases are restricted to a jurisdiction and have read replication on: ${join("; ", local.replicated_d1_in_jurisdiction)}. Replication keeps a copy of the data in every supported region, which is the opposite of what the jurisdiction was set to achieve. Set read_replication_mode = \"disabled\" on the database, check default_d1_read_replication_mode, or set allow_replicated_d1_in_jurisdiction = true if the jurisdiction was a latency preference rather than a compliance requirement."
    }

    precondition {
      condition     = length(local.missing_script_files) == 0
      error_message = "These Worker source files do not exist in layers/workers/: ${join("; ", local.missing_script_files)}. Worker source is committed to this layer rather than to an account tree, so the path is relative to var.worker_source_dir."
    }

    precondition {
      condition     = length(local.missing_kv_pairs_files) == 0
      error_message = "These KV data files do not exist in layers/workers/: ${join("; ", local.missing_kv_pairs_files)}. The path is relative to var.kv_data_dir."
    }

    precondition {
      condition     = length(local.duplicate_kv_file_keys) == 0
      error_message = "A KV data file repeats a key: ${join("; ", local.duplicate_kv_file_keys)}. Cloudflare's bulk format is a list, so a repeated key is accepted and the last one silently wins - which is how a redirect table ends up doing something nobody wrote down. Remove the duplicates."
    }

    precondition {
      condition     = length(local.oversized_kv_namespaces) == 0
      error_message = "These namespaces declare more pairs than Terraform should own: ${join("; ", local.oversized_kv_namespaces)}. Each pair is a resource in state, a line in every plan and an API call on every apply. Load a dataset this size from the pipeline with `wrangler kv bulk put --namespace-id <id> <file.json> --remote` against the namespace_id this layer outputs, and leave `pairs` empty - or raise max_managed_pairs on the namespace if it really is configuration."
    }

    precondition {
      condition     = length(local.duplicate_route_patterns) == 0
      error_message = "Two Workers claim the same route pattern: ${join(", ", local.duplicate_route_patterns)}. Cloudflare keeps one route per pattern, so whichever Worker applied last would win, and the plan cannot tell you which."
    }

    precondition {
      condition     = length(local.duplicate_custom_domain_hostnames) == 0
      error_message = "Two Workers claim the same custom domain hostname: ${join(", ", local.duplicate_custom_domain_hostnames)}. A hostname serves one Worker."
    }

    precondition {
      condition     = length(local.hostnames_claimed_by_route_and_domain) == 0
      error_message = "A route and a custom domain claim the same hostname: ${join("; ", local.hostnames_claimed_by_route_and_domain)}. A custom domain owns its hostname outright, so the route never fires - it reads as live configuration and is not."
    }

    precondition {
      condition     = length(local.route_hosts_outside_zone) == 0
      error_message = "A route pattern's hostname is not inside the zone it references: ${join("; ", local.route_hosts_outside_zone)}. Cloudflare would reject it only after creating the Worker, leaving the layer half-applied."
    }

    precondition {
      condition     = length(local.hostnames_outside_zone) == 0
      error_message = "A custom domain hostname is not inside the zone it references: ${join("; ", local.hostnames_outside_zone)}. Cloudflare would reject it only after creating the Worker, leaving the layer half-applied."
    }

    precondition {
      condition     = length(local.inline_secret_bindings) == 0
      error_message = "These bindings carry a secret as a literal value: ${join("; ", local.inline_secret_bindings)}. A secret_text binding puts the secret in the variable file, in the plan output and in Terraform state - three copies outside Cloudflare, none of which rotate with it. Use a secrets_store_secret binding, which references Cloudflare Secrets Store by store_id and secret_name and never passes the value through Terraform, or set allow_inline_secret_text = true in layers/workers/defaults.auto.tfvars on a pull request that says why."
    }

    precondition {
      condition     = length(local.unpinned_compatibility_dates) == 0
      error_message = "These Workers have no compatibility_date: ${join("; ", local.unpinned_compatibility_dates)}. Without one, Cloudflare pins the runtime to whenever the Worker was last uploaded, so redeploying unchanged code can change behaviour and nothing in the plan says so. Set default_compatibility_date in layers/workers/defaults.auto.tfvars, or a per-Worker date, or set allow_unpinned_compatibility_date = true."
    }

    precondition {
      condition     = length(local.observability_disabled) == 0
      error_message = "These Workers have Workers Logs switched off: ${join("; ", local.observability_disabled)}. A Worker on a route is in the request path, and logging cannot be turned on retroactively for the requests you needed. If the concern is volume, set observability.head_sampling_rate instead, or set allow_disabled_observability = true in layers/workers/defaults.auto.tfvars."
    }

    # Tags are written after the apply by a job that only sees the output, so a
    # bad key would otherwise surface there - after this plan was approved.
    precondition {
      condition     = length(local.resource_tag_problems) == 0
      error_message = "resource_tags in accounts/<account>/tags.tfvars: ${join("; ", local.resource_tag_problems)}."
    }
  }
}
