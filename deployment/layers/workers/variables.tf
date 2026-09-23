# Layer workers - inputs.
#
# Cloudflare Workers and the state they sit on: the scripts, what they are
# allowed to reach, the KV namespaces, D1 databases and queues behind them, and
# the routes, custom domains and cron triggers that invoke them. Holds its own
# state, so an apply here can never propose destroying a zone.
#
# Config files:
#   accounts/<account>/account.tfvars - the account ID, shared with every layer
#   accounts/<account>/zones.tfvars   - the zone inventory, shared with every layer
#   accounts/<account>/workers.tfvars - the scripts and the storage they bind,
#                                       consumed only here
#
# Worker source lives in this directory under `scripts/`, not in an account tree:
# it is code, it is customer-agnostic, and it belongs where it can be reviewed as
# code. An account tree names the file it wants and configures the bindings.

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare Account ID this layer run targets. Workers and KV namespaces are account-scoped; a zone is involved only where a Worker is put on a route or a custom domain."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "zones" {
  description = <<-EOT
    Zone inventory: logical key => domain name. The same file the zones layer is
    given, so the keys mean the same thing in both.

    This layer does not create zones. It looks up only the zones a route or a
    custom domain actually references, to get their IDs (see zone_lookup.tf),
    which keeps the two layers' states independent. A deployment of Workers with
    no routes costs no API call here.

    - `domain_name` - The apex domain (e.g. example.com).
    - `zone_tier`   - (Optional) The zone's Cloudflare rate plan. Unused by this
                      layer, and declared only so that the shared inventory file
                      can carry it for the zones and waf layers, which do gate on
                      it. Terraform rejects a .tfvars attribute that the variable
                      type does not declare, so omitting it here would break
                      every layer's run rather than just this one's.
  EOT
  type = map(object({
    domain_name = string
    zone_tier   = optional(string)
  }))

  validation {
    condition     = alltrue([for key in keys(var.zones) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "zones keys must be lowercase alphanumeric with underscores."
  }
}

variable "kv_namespaces" {
  description = <<-EOT
    Workers KV namespaces, keyed by a logical key. A Worker binding refers to a
    namespace by that key, so no account tree ever carries a namespace ID.

    - `title`             - Name shown in the dashboard. Cloudflare allows
                            duplicates, so include the environment or the brand.
    - `pairs`             - (Optional) Key/value pairs Terraform owns, written
                            inline. For configuration-shaped data only; see
                            `max_managed_pairs`.
    - `pairs_file`        - (Optional) A JSON file under `var.kv_data_dir`
                            holding the same thing, in Cloudflare's bulk format:
                            a list of `{ "key", "value", "base64", "metadata" }`
                            objects, which is what `wrangler kv bulk put` and the
                            KV bulk API both take. Mutually exclusive with
                            `pairs`.
    - `max_managed_pairs` - (Optional) Per-namespace override of
                            `var.default_max_managed_kv_pairs`.

    HOW BULK DATA SHOULD ACTUALLY GET IN
    A namespace holding tens of thousands of rows - a redirect table, a product
    catalogue - does not belong in Terraform state. Terraform writes one key per
    API call, keeps every value in state, and re-plans all of them every run.
    Declare the namespace here, leave `pairs` empty, and load it from the pipeline
    against the namespace ID this layer outputs:

      wrangler kv bulk put ./data/bulk/redirects-uk.json --namespace-id "$NAMESPACE_ID" --remote

    That is the supported replacement for hand-rolled curl loops against the KV
    bulk endpoint, and it keeps the data out of the plan while Terraform still
    owns the namespace, the Worker and the binding.

    SECURITY: pairs written here are stored in Terraform state in plain text and
    appear in plan output. Nothing secret goes in KV through this layer.
  EOT
  type = map(object({
    title             = string
    pairs             = optional(map(object({ value = string, metadata = optional(string) })))
    pairs_file        = optional(string)
    max_managed_pairs = optional(number)
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.kv_namespaces) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "kv_namespaces keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
  }

  validation {
    condition = alltrue([
      for namespace in var.kv_namespaces : !(namespace.pairs != null && namespace.pairs_file != null)
    ])
    error_message = "A kv_namespaces entry sets both pairs and pairs_file. They are two spellings of the same thing, and Terraform would have to pick one - say which you mean."
  }

  validation {
    condition = alltrue([
      for namespace in var.kv_namespaces :
      namespace.pairs_file == null || can(regex("^[A-Za-z0-9._/-]+\\.json$", coalesce(namespace.pairs_file, "x.json")))
    ])
    error_message = "Each kv_namespaces[*].pairs_file must be a .json path relative to var.kv_data_dir, with no traversal or backslashes."
  }

  validation {
    condition = alltrue([
      for namespace in var.kv_namespaces :
      namespace.pairs_file == null || !strcontains(coalesce(namespace.pairs_file, ""), "..")
    ])
    error_message = "A kv_namespaces[*].pairs_file walks out of var.kv_data_dir with \"..\". Keep KV data inside the layer."
  }
}

variable "d1_databases" {
  description = <<-EOT
    D1 databases, keyed by a logical key. A Worker binding refers to a database by
    that key, so no account tree ever carries a database UUID.

    - `name`                  - Database name, as the dashboard and
                                `wrangler d1` show it. Unique within the account.
    - `primary_location_hint` - (Optional) Region the primary is placed in: wnam,
                                enam, weur, eeur, apac or oc. Falls back to
                                `var.default_d1_primary_location_hint`. Honoured
                                at creation only.
    - `jurisdiction`          - (Optional) Data residency restriction: eu,
                                fedramp or us. Fixed at creation, and not the
                                same thing as a location hint - this one is a
                                constraint rather than a preference.
    - `read_replication_mode` - (Optional) "auto" or "disabled". Falls back to
                                `var.default_d1_read_replication_mode`.

    SCHEMA AND DATA ARE NOT MANAGED HERE
    Terraform owns the database and the binding; the tables inside it belong to
    the application. A migration is an ordered, one-way change that has to be
    applied in sequence, which is not what a plan reconciling desired state does.

    Migrations are committed to this layer, in a directory named for the same key
    used here:

      layers/workers/migrations/<key>/0001_initial_schema.sql

    .github/scripts/d1-migrations.sh applies them after every apply, against the
    ID this layer outputs. See layers/workers/migrations/README.md.

    EVERY FIELD HERE IS REPLACE-ON-CHANGE
    Cloudflare fixes the name, jurisdiction and location when the database is
    created. Editing any of them destroys the database and creates another, and a
    destroyed D1 database takes every row with it - there is no snapshot and no
    undo. A plan that proposes replacing a database is a plan to lose its data;
    read it as such and export first.
  EOT
  type = map(object({
    name                  = string
    primary_location_hint = optional(string)
    jurisdiction          = optional(string)
    read_replication_mode = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.d1_databases) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "d1_databases keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
  }

  validation {
    condition     = length(distinct([for database in var.d1_databases : lower(database.name)])) == length(var.d1_databases)
    error_message = "Two d1_databases entries share a name. A D1 database name is unique within an account, so the second create is refused after the first has been made."
  }

  validation {
    condition = alltrue([
      for database in var.d1_databases :
      database.primary_location_hint == null || contains(["wnam", "enam", "weur", "eeur", "apac", "oc"], coalesce(database.primary_location_hint, "wnam"))
    ])
    error_message = "Each d1_databases[*].primary_location_hint must be null or one of: wnam, enam, weur, eeur, apac, oc."
  }

  validation {
    condition = alltrue([
      for database in var.d1_databases :
      database.jurisdiction == null || contains(["eu", "fedramp", "us"], coalesce(database.jurisdiction, "eu"))
    ])
    error_message = "Each d1_databases[*].jurisdiction must be null or one of: eu, fedramp, us."
  }

  validation {
    condition = alltrue([
      for database in var.d1_databases :
      database.read_replication_mode == null || contains(["auto", "disabled"], coalesce(database.read_replication_mode, "auto"))
    ])
    error_message = "Each d1_databases[*].read_replication_mode must be null, \"auto\" or \"disabled\"."
  }
}

variable "queues" {
  description = <<-EOT
    Cloudflare queues, keyed by a logical key. A Worker producing to a queue binds
    it by that key, so no account tree carries a queue ID.

    - `name`                     - Queue name. Unique within the account, and how
                                   another queue names it as a dead letter queue.
    - `delivery_delay`           - (Optional) Seconds every message waits before a
                                   consumer may see it.
    - `delivery_paused`          - (Optional) Stops delivery while producers carry
                                   on writing. Declared either way, so a queue
                                   paused in the dashboard is un-paused by the
                                   next apply rather than quietly filling up.
    - `message_retention_period` - (Optional) Seconds an unconsumed message is
                                   kept, 60 to 1209600. Falls back to
                                   `var.default_queue_message_retention_period`,
                                   and to Cloudflare's four days below that.
    - `consumer`                 - (Optional) The one thing that reads the queue.

    CONSUMER
    A queue has exactly one consumer. One Worker may consume several queues, and
    any number of Workers may produce to one.

      - `type`                  - "worker" (default) for push delivery into a
                                  Worker's queue() handler, or "http_pull".
      - `worker_key`            - a key from `var.worker_scripts`, resolved to
                                  that Worker's name. Use this rather than
                                  `script_name` for a Worker this layer owns: the
                                  reference is also what makes Terraform deploy
                                  the Worker before attaching the consumer.
      - `script_name`           - a Worker owned elsewhere, named directly.
      - `dead_letter_queue_key` - a key from this same map, resolved to that
                                  queue's name.
      - `dead_letter_queue`     - a queue owned elsewhere, named directly.
      - `settings`              - batch_size, max_concurrency, max_retries,
                                  max_wait_time_ms, retry_delay and
                                  visibility_timeout_ms. See the queue_consumer
                                  module's `settings` description for what each
                                  one does and which consumer type it applies to.

    WHAT A QUEUE IS FOR
    A producer writes and returns; the consumer runs later, retries on failure,
    and cannot make the visitor wait. That is the whole point - work that must not
    fail the request, and work that is slower than the request. It is also why an
    unconsumed queue is dangerous rather than idle: producers keep succeeding
    while the backlog ages out at the retention period, and nothing reports what
    was dropped.
  EOT
  type = map(object({
    name                     = string
    delivery_delay           = optional(number)
    delivery_paused          = optional(bool, false)
    message_retention_period = optional(number)

    consumer = optional(object({
      type = optional(string, "worker")

      # Resolved by this layer from the logical keys above.
      worker_key            = optional(string)
      dead_letter_queue_key = optional(string)

      # Passed through to the module unchanged, for a Worker or a queue this
      # layer does not own.
      script_name       = optional(string)
      dead_letter_queue = optional(string)

      settings = optional(object({
        batch_size            = optional(number)
        max_concurrency       = optional(number)
        max_retries           = optional(number)
        max_wait_time_ms      = optional(number)
        retry_delay           = optional(number)
        visibility_timeout_ms = optional(number)
      }), {})
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.queues) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "queues keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
  }

  validation {
    condition     = length(distinct([for queue in var.queues : lower(queue.name)])) == length(var.queues)
    error_message = "Two queues entries share a name. A queue name is unique within an account, so the second would adopt or overwrite the first."
  }

  validation {
    condition     = alltrue([for queue in var.queues : queue.consumer == null || contains(["worker", "http_pull"], queue.consumer.type)])
    error_message = "Each queues[*].consumer.type must be \"worker\" or \"http_pull\"."
  }

  validation {
    condition = alltrue([
      for queue in var.queues :
      queue.consumer == null || !(queue.consumer.worker_key != null && queue.consumer.script_name != null)
    ])
    error_message = "A queue consumer sets both worker_key and script_name. Use worker_key for a Worker this layer owns - it is what orders the deploy before the consumer - and script_name for one it does not."
  }

  validation {
    condition = alltrue([
      for queue in var.queues :
      queue.consumer == null || !(queue.consumer.dead_letter_queue_key != null && queue.consumer.dead_letter_queue != null)
    ])
    error_message = "A queue consumer sets both dead_letter_queue_key and dead_letter_queue. Use the key for a queue this layer declares, so the account tree names a queue rather than repeating a string."
  }

  validation {
    condition = alltrue([
      for queue in var.queues :
      queue.consumer == null || queue.consumer.type != "worker" ||
      queue.consumer.worker_key != null || queue.consumer.script_name != null
    ])
    error_message = "A queue consumer of type \"worker\" names no Worker. Set worker_key for a Worker this layer owns, or script_name for one owned elsewhere."
  }

  validation {
    condition = alltrue([
      for queue in var.queues :
      queue.delivery_delay == null || (coalesce(queue.delivery_delay, 0) >= 0 && coalesce(queue.delivery_delay, 0) <= 86400)
    ])
    error_message = "Each queues[*].delivery_delay must be between 0 and 86400 seconds (24 hours)."
  }

  validation {
    condition = alltrue([
      for queue in var.queues :
      queue.message_retention_period == null ||
      (coalesce(queue.message_retention_period, 60) >= 60 && coalesce(queue.message_retention_period, 60) <= 1209600)
    ])
    error_message = "Each queues[*].message_retention_period must be between 60 and 1209600 seconds (14 days)."
  }
}

variable "worker_scripts" {
  description = <<-EOT
    Workers, keyed by a logical key. The key is the Terraform address; `name` is
    the Worker's identity in Cloudflare, and renaming either replaces the Worker.

    - `name`                - Worker name. Unique within the account. Include the
                              environment: two deployments sharing a name is two
                              pipelines overwriting each other.
    - `script_file`         - Source file, relative to `var.worker_source_dir` in
                              this layer directory. Its contents stay out of
                              state; a change to the file is what triggers a
                              redeploy.
    - `script_format`       - (Optional) "module" (default) or "service_worker".
                              Module syntax gives the script `env` and is what new
                              Workers should use; service worker syntax injects
                              bindings as globals and exists for inherited code.
    - `compatibility_date`  - (Optional) Runtime pin, YYYY-MM-DD. Falls back to
                              `var.default_compatibility_date`.
    - `compatibility_flags` - (Optional) Runtime feature flags, e.g.
                              ["nodejs_compat"].
    - `usage_model`         - (Optional) standard, bundled or unbound.
    - `placement_mode`      - (Optional) "smart" to run the Worker near its origin
                              instead of near the visitor. Helps a Worker that
                              talks to one back end repeatedly; hurts one that
                              answers from the edge.
    - `logpush`             - (Optional) Ship logs to a Logpush job defined
                              elsewhere.
    - `limits`              - (Optional) cpu_ms and subrequests ceilings per
                              invocation.
    - `observability`       - (Optional) Workers Logs settings. Falls back to
                              `var.default_observability`, which has it on.
    - `tail_consumers`      - (Optional) Workers that receive this one's execution
                              events. A tail consumer sees request URLs, headers
                              and anything logged.
    - `bindings`            - (Optional) What the Worker can reach. See below.
    - `routes`              - (Optional) `{ zone_key, pattern }`. The pattern is
                              host and path, e.g. "www.example.com/*", and its
                              host must sit inside the referenced zone.
    - `custom_domains`      - (Optional) `{ zone_key, hostname }`. Cloudflare
                              writes the DNS record and issues the certificate, so
                              the hostname must NOT also appear in dns.tfvars.
    - `cron_schedules`      - (Optional) Cron expressions invoking the Worker's
                              `scheduled` handler.

    BINDINGS
    Each entry needs `name` (how the script sees it, as `env.NAME`) and `type`.
    Four of the fields are resolved by this layer rather than passed through:

      - `kv_namespace_key` - a key from `var.kv_namespaces`, resolved to that
                             namespace's ID. Use this rather than `namespace_id`
                             so no account tree carries a hex string.
      - `d1_database_key`  - a key from `var.d1_databases`, resolved to that
                             database's UUID, for a `d1` binding.
      - `queue_key`        - a key from `var.queues`, resolved to that queue's
                             name, for a `queue` binding. This is the producer
                             side: a Worker with this binding writes to the
                             queue, and the consumer is declared on the queue
                             itself.
      - `worker_key`       - a key from `var.worker_scripts`, resolved to that
                             Worker's name, for a `service` binding between two
                             Workers this layer owns.

    Everything else is passed straight to the module: `bucket_name` for r2_bucket,
    `text` for plain_text, `json` for json, `store_id` + `secret_name` for
    secrets_store_secret, and so on. The module's `bindings` description carries
    the full table.

    A binding is a capability. Anything reachable through `env` is reachable by
    every code path in the Worker, including one an attacker reaches through a
    parsing bug. Bind the namespace it needs, not the account's.
  EOT
  type = map(object({
    name          = string
    script_file   = string
    script_format = optional(string, "module")

    compatibility_date  = optional(string)
    compatibility_flags = optional(list(string))
    usage_model         = optional(string)
    placement_mode      = optional(string)
    logpush             = optional(bool)

    limits = optional(object({
      cpu_ms      = optional(number)
      subrequests = optional(number)
    }))

    observability = optional(object({
      enabled            = optional(bool)
      head_sampling_rate = optional(number)
      logs_enabled       = optional(bool)
      invocation_logs    = optional(bool)
    }))

    tail_consumers = optional(list(object({
      service     = string
      environment = optional(string)
      namespace   = optional(string)
    })), [])

    bindings = optional(list(object({
      name = string
      type = string

      # Resolved by this layer from the logical keys above.
      kv_namespace_key = optional(string)
      d1_database_key  = optional(string)
      queue_key        = optional(string)
      worker_key       = optional(string)

      # Passed through to the module unchanged.
      namespace_id   = optional(string)
      bucket_name    = optional(string)
      jurisdiction   = optional(string)
      text           = optional(string)
      json           = optional(string)
      service        = optional(string)
      entrypoint     = optional(string)
      environment    = optional(string)
      class_name     = optional(string)
      script_name    = optional(string)
      database_id    = optional(string)
      id             = optional(string)
      queue_name     = optional(string)
      dataset        = optional(string)
      index_name     = optional(string)
      workflow_name  = optional(string)
      pipeline       = optional(string)
      certificate_id = optional(string)
      store_id       = optional(string)
      secret_name    = optional(string)
      simple = optional(object({
        limit              = number
        period             = number
        mitigation_timeout = optional(number)
      }))
    })), [])

    routes = optional(list(object({
      zone_key = string
      pattern  = string
    })), [])

    custom_domains = optional(list(object({
      zone_key = string
      hostname = string
    })), [])

    cron_schedules = optional(list(string), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.worker_scripts) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "worker_scripts keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
  }

  validation {
    condition     = length(distinct([for script in var.worker_scripts : lower(script.name)])) == length(var.worker_scripts)
    error_message = "Two worker_scripts entries share a name. A Worker name is unique within an account, so the second would adopt or overwrite the first's Worker."
  }

  validation {
    condition     = alltrue([for script in var.worker_scripts : contains(["module", "service_worker"], script.script_format)])
    error_message = "Each worker_scripts[*].script_format must be \"module\" or \"service_worker\"."
  }

  validation {
    condition = alltrue([
      for script in var.worker_scripts :
      can(regex("^[A-Za-z0-9._/-]+$", script.script_file)) && !strcontains(script.script_file, "..")
    ])
    error_message = "Each worker_scripts[*].script_file must be a path relative to var.worker_source_dir, with no traversal or backslashes. Worker source lives in this layer, not in an account tree."
  }

  validation {
    condition = alltrue(flatten([
      for script in var.worker_scripts : [
        for binding in script.bindings :
        !(binding.kv_namespace_key != null && binding.namespace_id != null)
      ]
    ]))
    error_message = "A binding sets both kv_namespace_key and namespace_id. Use kv_namespace_key so the account tree names a namespace rather than a hex ID."
  }

  validation {
    condition = alltrue(flatten([
      for script in var.worker_scripts : [
        for binding in script.bindings : !(binding.worker_key != null && binding.service != null)
      ]
    ]))
    error_message = "A binding sets both worker_key and service. Use worker_key for a Worker this layer owns, and service for one it does not."
  }

  validation {
    condition = alltrue(flatten([
      for script in var.worker_scripts : [
        for binding in script.bindings : binding.type == "kv_namespace" || binding.kv_namespace_key == null
      ]
    ]))
    error_message = "kv_namespace_key is set on a binding that is not of type kv_namespace. It would be silently ignored."
  }

  validation {
    condition = alltrue(flatten([
      for script in var.worker_scripts : [
        for binding in script.bindings :
        !(binding.d1_database_key != null && binding.database_id != null)
      ]
    ]))
    error_message = "A binding sets both d1_database_key and database_id. Use d1_database_key so the account tree names a database rather than a UUID."
  }

  validation {
    condition = alltrue(flatten([
      for script in var.worker_scripts : [
        for binding in script.bindings : binding.type == "d1" || binding.d1_database_key == null
      ]
    ]))
    error_message = "d1_database_key is set on a binding that is not of type d1. It would be silently ignored."
  }

  validation {
    condition = alltrue(flatten([
      for script in var.worker_scripts : [
        for binding in script.bindings :
        !(binding.queue_key != null && binding.queue_name != null)
      ]
    ]))
    error_message = "A binding sets both queue_key and queue_name. Use queue_key for a queue this layer declares, and queue_name for one it does not."
  }

  validation {
    condition = alltrue(flatten([
      for script in var.worker_scripts : [
        for binding in script.bindings : binding.type == "queue" || binding.queue_key == null
      ]
    ]))
    error_message = "queue_key is set on a binding that is not of type queue. It would be silently ignored."
  }
}

# Platform defaults (defaults.auto.tfvars in this directory)
variable "worker_source_dir" {
  type        = string
  default     = "scripts"
  description = <<-EOT
    Directory inside this layer holding Worker source, which
    `worker_scripts[*].script_file` is resolved against.

    Kept configurable rather than hardcoded so a deployment can point at a
    directory a build step writes into - but the default is the right answer for
    a Worker small enough to commit as-is, which is what a redirect or header
    Worker should be.
  EOT
}

variable "kv_data_dir" {
  type        = string
  default     = "data/kv"
  description = <<-EOT
    Directory inside this layer holding the JSON files that
    `kv_namespaces[*].pairs_file` is resolved against.

    Anything in here is committed, reviewed and ends up in Terraform state, so it
    is for configuration data rather than for a bulk dataset - see the
    `kv_namespaces` description for where a large one should go instead.
  EOT
}

variable "default_compatibility_date" {
  type        = string
  default     = null
  description = <<-EOT
    Runtime pin given to any Worker that names none, as YYYY-MM-DD.

    A fleet-wide date is worth having: left null, Cloudflare picks one per upload,
    so redeploying unchanged code can change how it behaves and nothing in the
    plan says so. Moving this forward is a deliberate change that re-plans every
    Worker at once, which is exactly the review it deserves.
  EOT

  validation {
    condition     = var.default_compatibility_date == null || can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", coalesce(var.default_compatibility_date, "1970-01-01")))
    error_message = "default_compatibility_date must be a bare date in YYYY-MM-DD form, e.g. \"2025-09-01\"."
  }
}

variable "default_compatibility_flags" {
  type        = list(string)
  default     = []
  description = "Runtime feature flags given to any Worker that names none. Empty is the right default - a flag is an opt-in to behaviour the pinned compatibility_date does not yet imply, and applying one fleet-wide affects Workers nobody tested it against."
}

variable "default_usage_model" {
  type        = string
  default     = null
  description = <<-EOT
    Billing and CPU model given to any Worker that names none. Null keeps the
    account default, which is almost always right.

    "bundled" and "unbound" are the retired pre-2023 models, accepted only on
    accounts that still carry them.
  EOT

  validation {
    condition     = var.default_usage_model == null || contains(["standard", "bundled", "unbound"], coalesce(var.default_usage_model, "standard"))
    error_message = "default_usage_model must be null or one of: standard, bundled, unbound."
  }
}

variable "default_placement_mode" {
  type        = string
  default     = null
  description = <<-EOT
    Smart Placement setting given to any Worker that names none. Null runs each
    Worker at the edge the request landed on.

    Do not set this fleet-wide. Smart Placement moves a Worker nearer its origin,
    which helps one that makes several round trips per request and adds latency to
    one that answers from the edge or from KV. It is a per-Worker decision.
  EOT

  validation {
    condition     = var.default_placement_mode == null || contains(["smart", "targeted"], coalesce(var.default_placement_mode, "smart"))
    error_message = "default_placement_mode must be null, \"smart\" or \"targeted\"."
  }
}

variable "default_logpush" {
  type        = bool
  default     = false
  description = "Whether a Worker that says nothing about it has Logpush turned on. Off by default because it does nothing without a Logpush job configured elsewhere, and turning it on without one reads in the dashboard as though logs are being shipped."
}

variable "default_observability" {
  type = object({
    enabled            = optional(bool, true)
    head_sampling_rate = optional(number)
    logs_enabled       = optional(bool, true)
    invocation_logs    = optional(bool, true)
  })
  default     = {}
  description = <<-EOT
    Workers Logs settings applied to any Worker that declares none.

    On by default. A Worker sits in the request path, and logging cannot be
    applied retroactively to the requests you needed - the choice is made before
    the incident, not during it. Sample a high-volume Worker with
    `head_sampling_rate` rather than turning it off.
  EOT

  validation {
    condition = (
      var.default_observability.head_sampling_rate == null ||
      (coalesce(var.default_observability.head_sampling_rate, 1) >= 0 && coalesce(var.default_observability.head_sampling_rate, 1) <= 1)
    )
    error_message = "default_observability.head_sampling_rate must be between 0 and 1, where 1 is every request."
  }
}

variable "default_max_managed_kv_pairs" {
  type        = number
  default     = 500
  description = <<-EOT
    Ceiling on how many KV pairs Terraform will manage in one namespace, unless
    that namespace overrides it.

    The limit is about Terraform, not about KV. Each managed pair is a resource in
    state, a line in every plan and an API call on every apply, so a few hundred is
    configuration and tens of thousands is a dataset that belongs in a
    `wrangler kv bulk put` step instead. See the `kv_namespaces` description.
  EOT

  validation {
    condition     = var.default_max_managed_kv_pairs >= 0
    error_message = "default_max_managed_kv_pairs must be zero or greater."
  }
}

variable "default_d1_primary_location_hint" {
  type        = string
  default     = null
  description = <<-EOT
    Region given to any D1 database that names none: wnam, enam, weur, eeur, apac
    or oc. Null lets Cloudflare place each database where it is first written
    from.

    The primary executes every write, so a fleet-wide value is worth setting where
    the writing workload lives in one place. Cloudflare honours it at creation
    only - changing it later moves nothing, and the database has to be recreated
    to land somewhere else.
  EOT

  validation {
    condition     = var.default_d1_primary_location_hint == null || contains(["wnam", "enam", "weur", "eeur", "apac", "oc"], coalesce(var.default_d1_primary_location_hint, "wnam"))
    error_message = "default_d1_primary_location_hint must be null or one of: wnam, enam, weur, eeur, apac, oc."
  }
}

variable "default_d1_read_replication_mode" {
  type        = string
  default     = null
  description = <<-EOT
    Read replication given to any D1 database that says nothing about it: "auto",
    "disabled", or null to leave the account default alone.

    "auto" costs nothing extra and does nothing on its own - a Worker only reads
    from a replica when it uses the D1 Sessions API, and a replica is eventually
    consistent. Set it fleet-wide only where the Workers reading these databases
    are written for it; a database under a `jurisdiction` is the case where it
    actively works against the configuration, which
    `allow_replicated_d1_in_jurisdiction` gates.
  EOT

  validation {
    condition     = var.default_d1_read_replication_mode == null || contains(["auto", "disabled"], coalesce(var.default_d1_read_replication_mode, "auto"))
    error_message = "default_d1_read_replication_mode must be null, \"auto\" or \"disabled\"."
  }
}

variable "default_queue_message_retention_period" {
  type        = number
  default     = null
  description = <<-EOT
    Seconds an unconsumed message is kept on any queue that names no period, 60 to
    1209600 (14 days). Null leaves Cloudflare's default of four days.

    Retention is what a broken consumer is measured against: it is the time
    available to notice and fix one before messages start expiring, and nothing
    reports the ones that went. Four days covers a weekend; a queue whose work
    cannot be lost wants longer, and a queue of cache invalidations that are
    worthless after an hour wants less.
  EOT

  validation {
    condition = (
      var.default_queue_message_retention_period == null ||
      (coalesce(var.default_queue_message_retention_period, 60) >= 60 && coalesce(var.default_queue_message_retention_period, 60) <= 1209600)
    )
    error_message = "default_queue_message_retention_period must be null or between 60 and 1209600 seconds (14 days)."
  }
}

# Guardrails
variable "allow_inline_secret_text" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether a Worker may carry a `secret_text` binding.

    A secret_text binding holds the literal secret. It is written into a variable
    file, printed in a plan, and stored in Terraform state - three copies outside
    Cloudflare, none of which rotate when the secret does.

    Left false, such a binding fails the plan naming the Worker. The replacement
    is a `secrets_store_secret` binding, which references a secret in Cloudflare
    Secrets Store by `store_id` and `secret_name`: the Worker sees the same string
    on `env`, and Terraform never handles the value at all.

    Turn this on only to keep an inherited Worker running while its secret is
    moved, on a pull request that says so.
  EOT
}

variable "allow_unpinned_compatibility_date" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether a Worker may be deployed with no `compatibility_date`.

    Without one, Cloudflare assigns the date of the upload, so the runtime a
    Worker gets depends on when it was last deployed. Two Workers running
    identical code behave differently, and a redeploy of unchanged source can
    change behaviour with nothing in the plan to show it.

    Left false, a Worker with neither its own date nor
    `var.default_compatibility_date` fails the plan. Setting the fleet default is
    the usual fix.
  EOT
}

variable "allow_disabled_observability" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether a Worker may be deployed with Workers Logs switched off.

    A Worker on a route is in the request path for real traffic. With logging off
    there is no record that it ran, what it returned, or why - and it cannot be
    turned on after the fact for requests that have already happened.

    Left false, a Worker asking for it fails the plan by name. If the concern is
    volume or cost, set `head_sampling_rate` instead: a tenth of the requests
    still answers "is it working".
  EOT
}

variable "allow_queues_without_consumer" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether a queue may be declared with nothing reading it.

    Such a queue is not idle - it is accepting messages. Producers keep
    succeeding, the backlog grows, and each message is dropped when it reaches the
    retention period, with nothing raising an error and nothing recording what was
    lost. It looks healthy from every direction except the one that matters.

    Left false, a queue with no `consumer` fails the plan by name. A queue that
    another queue names as its dead letter queue is exempt: a holding pen for
    failed messages is meant to accumulate, and is drained by hand or by a
    separate consumer once the cause is fixed.

    Turn it on where a consumer genuinely lives elsewhere - a pull consumer
    outside this pipeline, or a Worker deployed from its own repository - on a
    pull request that says which.
  EOT
}

variable "allow_queue_consumer_without_dead_letter_queue" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether a queue's consumer may be configured with no dead letter queue.

    Without one, a message that fails `max_retries` times is deleted. No error,
    no log line naming it, no copy to look at afterwards - the batch that broke
    the consumer is exactly the batch nobody can examine.

    Left false, a consumer with neither `dead_letter_queue_key` nor
    `dead_letter_queue` fails the plan. The dead letter queue is usually another
    entry in `var.queues`, which costs nothing until something fails into it.

    Turn it on for a queue whose messages are genuinely disposable - cache
    invalidations, best-effort telemetry - on a pull request that says so.
  EOT
}

variable "allow_replicated_d1_in_jurisdiction" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether a D1 database under a `jurisdiction` may also have read replication
    turned on.

    A jurisdiction is set because something requires the data to stay in one
    place. Read replication asks Cloudflare to keep a copy of that data in every
    supported region and serve reads from the nearest - the two are answers to
    opposite questions, and the replication is the one that happens quietly.

    Left false, a database declaring both fails the plan by name. Turn it on only
    where the jurisdiction was a latency preference rather than a compliance
    requirement, in which case `primary_location_hint` says what was actually
    meant.
  EOT
}

# Resource tags (accounts/<account>/tags.tfvars)
variable "resource_tags" {
  description = <<-EOT
    Cloudflare resource tags. The same file reaches every layer that tags - zones,
    zerotrust, r2 and workers - and each reads `defaults`, `allowed_values` and
    its own section, ignoring the rest. Declared in full everywhere because
    Terraform rejects a .tfvars attribute the type does not declare.

    - `defaults`       - (Optional) Tags for every resource of every type.
    - `allowed_values` - (Optional) Tag key => the only values it may take, so
                         "prod" and "production" cannot split one filter.
    - `zones`, `access_applications`, `r2_buckets`, `kv_namespaces`,
      `d1_databases`, `queues`, `worker_scripts`
                       - (Optional) One per resource type, each with:
                           `defaults`  - tags for every resource of the type
                           `resources` - logical key => tags for one resource,
                                         keyed as in that type's own tfvars

    Later wins: defaults, then <type>.defaults, then <type>.resources[key]. A
    null value drops a key an earlier level set. `managed-by` and `layer` are
    set by the layer itself and rejected here.

    Nothing in Terraform calls the Tagging API - the provider has no resource
    for it. tags.tf resolves each resource's set and outputs it as
    `resource_tags`, and .github/scripts/resource-tags.sh applies it after the
    apply.
  EOT
  type = object({
    defaults       = optional(map(string), {})
    allowed_values = optional(map(list(string)), {})
    zones = optional(object({
      defaults  = optional(map(string), {})
      resources = optional(map(map(string)), {})
    }), {})
    access_applications = optional(object({
      defaults  = optional(map(string), {})
      resources = optional(map(map(string)), {})
    }), {})
    r2_buckets = optional(object({
      defaults  = optional(map(string), {})
      resources = optional(map(map(string)), {})
    }), {})
    kv_namespaces = optional(object({
      defaults  = optional(map(string), {})
      resources = optional(map(map(string)), {})
    }), {})
    d1_databases = optional(object({
      defaults  = optional(map(string), {})
      resources = optional(map(map(string)), {})
    }), {})
    queues = optional(object({
      defaults  = optional(map(string), {})
      resources = optional(map(map(string)), {})
    }), {})
    worker_scripts = optional(object({
      defaults  = optional(map(string), {})
      resources = optional(map(map(string)), {})
    }), {})
  })
  default = {}
}
