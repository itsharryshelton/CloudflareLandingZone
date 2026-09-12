# Applies the platform baseline, resolves logical keys to real IDs, loads any KV
# data files, and derives the preflight assertions, so that workers.tf reads as
# four plain module calls.

locals {
  # Only zones a route or a custom domain actually targets are looked up, so a
  # deployment of Workers with no triggers costs no API call - and can be planned
  # offline.
  referenced_zone_keys = distinct(flatten([
    for script in var.worker_scripts : concat(
      [for route in script.routes : route.zone_key],
      [for domain in script.custom_domains : domain.zone_key],
    )
  ]))

  referenced_zones = {
    for key, zone in var.zones : key => zone
    if contains(local.referenced_zone_keys, key)
  }

  # KV data files
  # Cloudflare's bulk format is a list, and a list can repeat a key. Grouped with
  # `...` so the duplicate is reported by name below rather than aborting inside
  # this file with Terraform's generic "Duplicate object key".
  #
  # fileexists() guards the read: file() on a missing path is a hard error that
  # would pre-empt the preflight message naming the file.
  kv_file_pairs_grouped = {
    for key, namespace in var.kv_namespaces : key => (
      namespace.pairs_file == null || !fileexists("${path.module}/${var.kv_data_dir}/${coalesce(namespace.pairs_file, "missing.json")}")
      ? {}
      : {
        for item in jsondecode(file("${path.module}/${var.kv_data_dir}/${namespace.pairs_file}")) :
        item.key => {
          value = try(item.base64, false) ? base64decode(item.value) : item.value
          # The API wants metadata as a string; a bulk file usually carries it as
          # an object, so anything that is not already a string is re-encoded.
          metadata = (
            try(item.metadata, null) == null ? null :
            can(tostring(item.metadata)) ? tostring(item.metadata) : jsonencode(item.metadata)
          )
        }...
      }
    )
  }

  kv_namespaces = {
    for key, namespace in var.kv_namespaces : key => {
      title = namespace.title

      # An inline `pairs` map wins; otherwise the file, if there is one. Both set
      # is rejected by variable validation rather than silently resolved here.
      pairs = (
        namespace.pairs != null
        ? namespace.pairs
        : { for name, group in local.kv_file_pairs_grouped[key] : name => group[0] }
      )

      max_managed_pairs = namespace.max_managed_pairs != null ? namespace.max_managed_pairs : var.default_max_managed_kv_pairs
    }
  }

  # D1
  d1_databases = {
    for key, database in var.d1_databases : key => {
      name = database.name

      primary_location_hint = database.primary_location_hint != null ? database.primary_location_hint : var.default_d1_primary_location_hint
      read_replication_mode = database.read_replication_mode != null ? database.read_replication_mode : var.default_d1_read_replication_mode

      # No fleet default on purpose. A jurisdiction is a compliance decision about
      # one database's data, and one applied to every database by a file nobody
      # re-reads is how a database ends up restricted for no reason anybody can
      # name - or unrestricted for the same reason.
      jurisdiction = database.jurisdiction
    }
  }

  # Queues
  # Split in two, and the split is load-bearing rather than tidy. `queues` is
  # derived from variables alone, so the queue itself can be created without
  # waiting on anything; `queue_consumers` resolves logical keys through module
  # outputs, which is what orders the consumer behind the Worker that serves it.
  #
  # Putting them in one local would close a loop: a producer's queue binding
  # reads module.queues, so a value feeding module.queues that also read
  # module.worker_scripts would make the queue wait on a Worker that is waiting
  # on the queue.
  queues = {
    for key, queue in var.queues : key => {
      name = queue.name

      settings = {
        delivery_delay           = queue.delivery_delay
        delivery_paused          = queue.delivery_paused
        message_retention_period = queue.message_retention_period != null ? queue.message_retention_period : var.default_queue_message_retention_period
      }
    }
  }

  queue_consumers = {
    for key, queue in var.queues : key => {
      type = queue.consumer.type

      # `try` rather than a bare index, so a key naming nothing reaches the
      # operator as the preflight message rather than as "Invalid index".
      script_name = (
        queue.consumer.worker_key != null
        ? try(module.worker_scripts[queue.consumer.worker_key].script_name, null)
        : queue.consumer.script_name
      )

      dead_letter_queue = (
        queue.consumer.dead_letter_queue_key != null
        ? try(module.queues[queue.consumer.dead_letter_queue_key].queue_name, null)
        : queue.consumer.dead_letter_queue
      )

      settings = queue.consumer.settings
    }
    if queue.consumer != null
  }

  # Workers
  # Per-Worker settings win; anything unset falls back to the platform baseline.
  #
  # Split in two on purpose. `worker_baseline` resolves everything that can be
  # decided from variables and from the filesystem, so preflight.tf can assert on
  # it at plan time. `worker_scripts` adds the parts that depend on a module
  # output or a data source, which are unknown until the KV namespaces exist - a
  # precondition reading those would be deferred to apply, which is exactly when
  # a guardrail is no longer useful.
  worker_baseline = {
    for key, script in var.worker_scripts : key => {
      name = script.name

      # The file's contents never enter state - the hash is what makes an edit
      # visible to a plan. Guarded by fileexists() so a typo'd path reaches the
      # operator as the preflight message rather than as a filesha256 error.
      content_file   = "${path.module}/${var.worker_source_dir}/${script.script_file}"
      content_sha256 = fileexists("${path.module}/${var.worker_source_dir}/${script.script_file}") ? filesha256("${path.module}/${var.worker_source_dir}/${script.script_file}") : null

      # Cloudflare cannot infer the syntax from the source, so exactly one of
      # these is set. The name is a label; keeping it as the real filename means
      # the dashboard shows what is in the repository.
      main_module = script.script_format == "module" ? basename(script.script_file) : null
      body_part   = script.script_format == "service_worker" ? basename(script.script_file) : null

      compatibility_date  = script.compatibility_date != null ? script.compatibility_date : var.default_compatibility_date
      compatibility_flags = script.compatibility_flags != null ? script.compatibility_flags : var.default_compatibility_flags
      usage_model         = script.usage_model != null ? script.usage_model : var.default_usage_model
      placement_mode      = script.placement_mode != null ? script.placement_mode : var.default_placement_mode
      logpush             = script.logpush != null ? script.logpush : var.default_logpush

      limits         = script.limits
      tail_consumers = script.tail_consumers
      cron_schedules = script.cron_schedules

      # Merged field by field rather than whole-object, so a Worker can lower its
      # sampling rate without also having to restate that logging is on.
      observability = {
        enabled            = try(script.observability.enabled, null) != null ? script.observability.enabled : coalesce(var.default_observability.enabled, true)
        head_sampling_rate = try(script.observability.head_sampling_rate, null) != null ? script.observability.head_sampling_rate : var.default_observability.head_sampling_rate
        logs_enabled       = try(script.observability.logs_enabled, null) != null ? script.observability.logs_enabled : coalesce(var.default_observability.logs_enabled, true)
        invocation_logs    = try(script.observability.invocation_logs, null) != null ? script.observability.invocation_logs : coalesce(var.default_observability.invocation_logs, true)
      }
    }
  }

  worker_scripts = {
    for key, script in var.worker_scripts : key => merge(local.worker_baseline[key], {

      # Logical keys resolved to real values. `try` rather than a bare index: a
      # key pointing at nothing must reach the operator as the preflight message
      # naming it, not as "Invalid index" pointing at this file.
      bindings = [
        for binding in script.bindings : {
          name = binding.name
          type = binding.type

          namespace_id = binding.kv_namespace_key != null ? try(module.kv_namespaces[binding.kv_namespace_key].namespace_id, null) : binding.namespace_id
          service      = binding.worker_key != null ? try(var.worker_scripts[binding.worker_key].name, null) : binding.service

          database_id = binding.d1_database_key != null ? try(module.d1_databases[binding.d1_database_key].database_id, null) : binding.database_id
          queue_name  = binding.queue_key != null ? try(module.queues[binding.queue_key].queue_name, null) : binding.queue_name

          bucket_name    = binding.bucket_name
          jurisdiction   = binding.jurisdiction
          text           = binding.text
          json           = binding.json
          entrypoint     = binding.entrypoint
          environment    = binding.environment
          class_name     = binding.class_name
          script_name    = binding.script_name
          id             = binding.id
          dataset        = binding.dataset
          index_name     = binding.index_name
          workflow_name  = binding.workflow_name
          pipeline       = binding.pipeline
          certificate_id = binding.certificate_id
          store_id       = binding.store_id
          secret_name    = binding.secret_name
          simple         = binding.simple
        }
      ]

      routes = [
        for route in script.routes : {
          pattern = route.pattern
          zone_id = data.cloudflare_zone.this[route.zone_key].id
        }
        if contains(keys(local.referenced_zones), route.zone_key)
      ]

      custom_domains = [
        for domain in script.custom_domains : {
          hostname  = lower(domain.hostname)
          zone_id   = data.cloudflare_zone.this[domain.zone_key].id
          zone_name = var.zones[domain.zone_key].domain_name
        }
        if contains(keys(local.referenced_zones), domain.zone_key)
      ]
    })
  }

  # Preflight checks here
  dangling_zone_keys = distinct(flatten([
    for key, script in var.worker_scripts : concat(
      [
        for route in script.routes : "worker_scripts.${key}.routes -> zone_key = \"${route.zone_key}\""
        if !contains(keys(var.zones), route.zone_key)
      ],
      [
        for domain in script.custom_domains : "worker_scripts.${key}.custom_domains -> zone_key = \"${domain.zone_key}\""
        if !contains(keys(var.zones), domain.zone_key)
      ],
    )
  ]))

  dangling_kv_namespace_keys = distinct(flatten([
    for key, script in var.worker_scripts : [
      for binding in script.bindings :
      "worker_scripts.${key}.bindings.${binding.name} -> kv_namespace_key = \"${binding.kv_namespace_key}\""
      if binding.kv_namespace_key != null && !contains(keys(var.kv_namespaces), coalesce(binding.kv_namespace_key, ""))
    ]
  ]))

  dangling_worker_keys = distinct(flatten([
    for key, script in var.worker_scripts : [
      for binding in script.bindings :
      "worker_scripts.${key}.bindings.${binding.name} -> worker_key = \"${binding.worker_key}\""
      if binding.worker_key != null && !contains(keys(var.worker_scripts), coalesce(binding.worker_key, ""))
    ]
  ]))

  dangling_d1_database_keys = distinct(flatten([
    for key, script in var.worker_scripts : [
      for binding in script.bindings :
      "worker_scripts.${key}.bindings.${binding.name} -> d1_database_key = \"${binding.d1_database_key}\""
      if binding.d1_database_key != null && !contains(keys(var.d1_databases), coalesce(binding.d1_database_key, ""))
    ]
  ]))

  dangling_queue_keys = distinct(flatten([
    for key, script in var.worker_scripts : [
      for binding in script.bindings :
      "worker_scripts.${key}.bindings.${binding.name} -> queue_key = \"${binding.queue_key}\""
      if binding.queue_key != null && !contains(keys(var.queues), coalesce(binding.queue_key, ""))
    ]
  ]))

  # The consumer side names two things by key: the Worker that reads the queue,
  # and the queue that failed messages land in.
  dangling_queue_consumer_worker_keys = distinct([
    for key, queue in var.queues :
    "queues.${key}.consumer -> worker_key = \"${queue.consumer.worker_key}\""
    if queue.consumer != null && try(queue.consumer.worker_key, null) != null
    && !contains(keys(var.worker_scripts), coalesce(try(queue.consumer.worker_key, null), ""))
  ])

  dangling_dead_letter_queue_keys = distinct([
    for key, queue in var.queues :
    "queues.${key}.consumer -> dead_letter_queue_key = \"${queue.consumer.dead_letter_queue_key}\""
    if queue.consumer != null && try(queue.consumer.dead_letter_queue_key, null) != null
    && !contains(keys(var.queues), coalesce(try(queue.consumer.dead_letter_queue_key, null), ""))
  ])

  # Queue wiring. Each of these is accepted by Cloudflare and produces a queue
  # that looks configured and loses messages.
  self_dead_letter_queues = distinct(concat(
    [
      for key, queue in var.queues : "queues.${key} (\"${queue.name}\")"
      if queue.consumer != null && try(queue.consumer.dead_letter_queue_key, null) == key
    ],
    [
      for key, queue in var.queues : "queues.${key} (\"${queue.name}\")"
      if queue.consumer != null && try(queue.consumer.dead_letter_queue, null) != null
      && lower(coalesce(try(queue.consumer.dead_letter_queue, null), "")) == lower(queue.name)
    ],
  ))

  # Queues another queue dead letters into, by key and by name. A holding pen for
  # failed messages is meant to fill up, so it is exempt from the check below.
  dead_letter_queue_targets = distinct(concat(
    [
      for key, queue in var.queues : coalesce(try(queue.consumer.dead_letter_queue_key, null), "")
      if queue.consumer != null && try(queue.consumer.dead_letter_queue_key, null) != null
    ],
    [
      for key, queue in var.queues : lower(coalesce(try(queue.consumer.dead_letter_queue, null), ""))
      if queue.consumer != null && try(queue.consumer.dead_letter_queue, null) != null
    ],
  ))

  queues_without_consumer = var.allow_queues_without_consumer ? [] : [
    for key, queue in var.queues : "queues.${key} (\"${queue.name}\")"
    if queue.consumer == null
    && !contains(local.dead_letter_queue_targets, key)
    && !contains(local.dead_letter_queue_targets, lower(queue.name))
  ]

  consumers_without_dead_letter_queue = var.allow_queue_consumer_without_dead_letter_queue ? [] : [
    for key, queue in var.queues : "queues.${key} (\"${queue.name}\")"
    if queue.consumer != null
    && try(queue.consumer.dead_letter_queue_key, null) == null
    && try(queue.consumer.dead_letter_queue, null) == null
  ]

  # D1. Replication is resolved rather than read from var, so a database that
  # inherits "auto" from the fleet default is caught as well as one that asks for
  # it.
  replicated_d1_in_jurisdiction = var.allow_replicated_d1_in_jurisdiction ? [] : [
    for key, database in local.d1_databases : "d1_databases.${key} (\"${database.name}\", jurisdiction \"${database.jurisdiction}\")"
    if database.jurisdiction != null && database.read_replication_mode == "auto"
  ]

  # Source and data files. Terraform reads these at plan time, so a missing one
  # is worth naming rather than letting filesha256 or file() report the path.
  missing_script_files = [
    for key, script in var.worker_scripts :
    "worker_scripts.${key}.script_file -> ${var.worker_source_dir}/${script.script_file}"
    if !fileexists("${path.module}/${var.worker_source_dir}/${script.script_file}")
  ]

  missing_kv_pairs_files = [
    for key, namespace in var.kv_namespaces :
    "kv_namespaces.${key}.pairs_file -> ${var.kv_data_dir}/${namespace.pairs_file}"
    if namespace.pairs_file != null && !fileexists("${path.module}/${var.kv_data_dir}/${coalesce(namespace.pairs_file, "missing.json")}")
  ]

  duplicate_kv_file_keys = flatten([
    for key, grouped in local.kv_file_pairs_grouped : [
      for name, group in grouped : "kv_namespaces.${key}.pairs_file -> \"${name}\" appears ${length(group)} times"
      if length(group) > 1
    ]
  ])

  oversized_kv_namespaces = [
    for key, namespace in local.kv_namespaces :
    "kv_namespaces.${key} (${length(namespace.pairs)} pairs, ceiling ${namespace.max_managed_pairs})"
    if length(namespace.pairs) > namespace.max_managed_pairs
  ]

  # Trigger collisions. Cloudflare accepts each of these and resolves them by
  # whichever apply ran last, which is not a thing a plan should decide.
  all_route_patterns = flatten([
    for key, script in var.worker_scripts : [for route in script.routes : lower(route.pattern)]
  ])

  duplicate_route_patterns = distinct([
    for pattern in local.all_route_patterns : pattern
    if length([for other in local.all_route_patterns : other if other == pattern]) > 1
  ])

  all_custom_domain_hostnames = flatten([
    for key, script in var.worker_scripts : [for domain in script.custom_domains : lower(domain.hostname)]
  ])

  duplicate_custom_domain_hostnames = distinct([
    for hostname in local.all_custom_domain_hostnames : hostname
    if length([for other in local.all_custom_domain_hostnames : other if other == hostname]) > 1
  ])

  # A custom domain owns its hostname outright, so a route on the same host - even
  # on a different Worker - is configuration that cannot do what it looks like.
  hostnames_claimed_by_route_and_domain = distinct([
    for pattern in local.all_route_patterns : "route \"${pattern}\" and a custom domain both claim \"${split("/", pattern)[0]}\""
    if contains(local.all_custom_domain_hostnames, split("/", pattern)[0])
  ])

  # Cloudflare rejects a route or a custom domain outside its zone, but only after
  # the Worker exists, leaving a half-applied layer behind.
  route_hosts_outside_zone = flatten([
    for key, script in var.worker_scripts : [
      for route in script.routes :
      "worker_scripts.${key}: route \"${route.pattern}\" is not within \"${var.zones[route.zone_key].domain_name}\""
      if contains(keys(var.zones), route.zone_key)
      && !endswith(lower(split("/", route.pattern)[0]), lower(var.zones[route.zone_key].domain_name))
    ]
  ])

  hostnames_outside_zone = flatten([
    for key, script in var.worker_scripts : [
      for domain in script.custom_domains :
      "worker_scripts.${key}: \"${domain.hostname}\" is not within \"${var.zones[domain.zone_key].domain_name}\""
      if contains(keys(var.zones), domain.zone_key)
      && !endswith(lower(domain.hostname), lower(var.zones[domain.zone_key].domain_name))
    ]
  ])

  # Governing defaults. Each of these is a configuration Cloudflare accepts
  # happily and that quietly costs somebody an afternoon later.
  inline_secret_bindings = var.allow_inline_secret_text ? [] : distinct(flatten([
    for key, script in var.worker_scripts : [
      for binding in script.bindings : "worker_scripts.${key}.bindings.${binding.name}"
      if binding.type == "secret_text"
    ]
  ]))

  unpinned_compatibility_dates = var.allow_unpinned_compatibility_date ? [] : [
    for key, script in local.worker_baseline : "worker_scripts.${key} (\"${script.name}\")"
    if script.compatibility_date == null
  ]

  observability_disabled = var.allow_disabled_observability ? [] : [
    for key, script in local.worker_baseline : "worker_scripts.${key} (\"${script.name}\")"
    if !script.observability.enabled
  ]
}
