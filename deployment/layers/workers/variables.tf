# Layer workers - inputs.
#
# Cloudflare Workers and Workers KV: the scripts, what they are allowed to reach,
# the namespaces behind them, and the routes, custom domains and cron triggers
# that invoke them. Holds its own state, so an apply here can never propose
# destroying a zone.
#
# Config files:
#   accounts/<account>/account.tfvars - the account ID, shared with every layer
#   accounts/<account>/zones.tfvars   - the zone inventory, shared with every layer
#   accounts/<account>/workers.tfvars - the namespaces and scripts, consumed only here
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
    Two of the fields are resolved by this layer rather than passed through:

      - `kv_namespace_key` - a key from `var.kv_namespaces`, resolved to that
                             namespace's ID. Use this rather than `namespace_id`
                             so no account tree carries a hex string.
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
      `worker_scripts` - (Optional) One per resource type, each with:
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
    worker_scripts = optional(object({
      defaults  = optional(map(string), {})
      resources = optional(map(map(string)), {})
    }), {})
  })
  default = {}
}
