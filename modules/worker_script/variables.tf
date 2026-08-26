variable "account_id" {
  type        = string
  description = "Cloudflare Account ID. Workers are account-scoped; a zone only enters the picture when the Worker is put on a route or a custom domain."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "script_name" {
  type        = string
  description = <<-EOT
    Name of the Worker. It is the Worker's identity in Cloudflare and appears in
    every route, so renaming one destroys the old Worker and creates a new one -
    briefly leaving the routes pointing at nothing.

    Include the environment in the name. Two Workers cannot share a name within an
    account, so "redirects-prod" and "redirects-dev" is the difference between two
    deployments and one deployment that two pipelines fight over.
  EOT

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9_-]{0,62}$", var.script_name))
    error_message = "script_name must be 1-63 characters of lowercase letters, numbers, hyphens or underscores, starting with a letter or number."
  }
}

# Source
variable "content" {
  type        = string
  default     = null
  description = <<-EOT
    Worker source, inline. Mutually exclusive with `content_file`, and exactly one
    of the two is required.

    Inline source is carried in Terraform state and printed in full the first time
    it is planned. That is acceptable for a few lines of glue and wrong for a
    bundle, so prefer `content_file`.
  EOT
}

variable "content_file" {
  type        = string
  default     = null
  description = <<-EOT
    Path to a file holding the Worker source. Mutually exclusive with `content`,
    and exactly one of the two is required.

    The file's contents stay out of state; `content_sha256` is what Terraform
    compares to decide whether a redeploy is needed, and so it must be supplied
    alongside. The path is resolved relative to the Terraform working directory,
    which is the calling root module - pass an absolute path built from
    `path.module` rather than a bare relative one.
  EOT
}

variable "content_sha256" {
  type        = string
  default     = null
  description = <<-EOT
    SHA-256 of the file named by `content_file`, normally `filesha256(...)`.
    Required with `content_file` and meaningless without it.

    This is the only thing that makes a source change visible to a plan: the file
    itself is never read into state, so without a hash that moves, editing the
    Worker would produce "No changes" and deploy nothing.
  EOT

  validation {
    condition     = var.content_sha256 == null || can(regex("^[0-9a-fA-F]{64}$", coalesce(var.content_sha256, "")))
    error_message = "content_sha256 must be a 64-character hexadecimal SHA-256 digest, as returned by filesha256()."
  }
}

variable "main_module" {
  type        = string
  default     = "worker.js"
  description = <<-EOT
    Filename recorded for the uploaded source when the Worker is written in ES
    module syntax - the modern form, `export default { async fetch(request, env) }`,
    where bindings arrive as `env.NAME`.

    Set this OR `body_part`, never both. `body_part` selects the older service
    worker syntax (`addEventListener("fetch", ...)`), where bindings are injected
    as globals; Cloudflare still runs those, but new Workers should not be written
    that way and several platform features are module-only.

    The name is a label rather than a lookup - nothing on disk has to match it -
    but it is what shows in the dashboard, so keep the extension honest: `.js` for
    a classic script, `.mjs` where the toolchain needs the module hint.
  EOT
}

variable "body_part" {
  type        = string
  default     = null
  description = <<-EOT
    Filename recorded for the uploaded source when the Worker is written in the
    older service worker syntax. Set this only to keep an inherited Worker working
    unchanged; set `main_module = null` at the same time.

    See `main_module` for why module syntax is the default.
  EOT
}

# Runtime
variable "compatibility_date" {
  type        = string
  default     = null
  description = <<-EOT
    Date, as YYYY-MM-DD, pinning which Workers runtime behaviour the script gets.
    Backwards-incompatible runtime fixes released after it do not reach this
    Worker.

    Null lets Cloudflare choose, which means the date drifts with each upload and
    a redeploy of unchanged code can change behaviour. Pin it. Moving it forward
    is a deliberate change with a plan attached, which is the whole point.
  EOT

  validation {
    condition     = var.compatibility_date == null || can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", coalesce(var.compatibility_date, "1970-01-01")))
    error_message = "compatibility_date must be a bare date in YYYY-MM-DD form, e.g. \"2025-09-01\"."
  }
}

variable "compatibility_flags" {
  type        = list(string)
  default     = []
  description = <<-EOT
    Runtime feature flags applied on top of `compatibility_date`, for opting into
    a change early or out of one late. `nodejs_compat` is the common entry.

    A flag that the pinned date already implies is accepted and does nothing, so a
    list here is worth re-reading when the date moves.
  EOT
}

variable "usage_model" {
  type        = string
  default     = null
  description = <<-EOT
    Billing and CPU model for invocations: "standard", "bundled" or "unbound".
    Null keeps the account default, which is what nearly every Worker should do.

    "bundled" and "unbound" are the retired pre-2023 models and are accepted only
    on accounts that still have them.
  EOT

  validation {
    condition     = var.usage_model == null || contains(["standard", "bundled", "unbound"], coalesce(var.usage_model, "standard"))
    error_message = "usage_model must be null or one of: standard, bundled, unbound."
  }
}

variable "placement_mode" {
  type        = string
  default     = null
  description = <<-EOT
    Smart Placement. "smart" lets Cloudflare run the Worker near its back end
    rather than near the visitor; null runs it at the edge the request landed on.

    Smart Placement helps a Worker that makes several round trips to one origin
    and hurts one that mostly answers from the edge - a redirect Worker reading KV
    is firmly the second kind, and should leave this null.
  EOT

  validation {
    condition     = var.placement_mode == null || contains(["smart", "targeted"], coalesce(var.placement_mode, "smart"))
    error_message = "placement_mode must be null, \"smart\" or \"targeted\"."
  }
}

variable "limits" {
  type = object({
    cpu_ms      = optional(number)
    subrequests = optional(number)
  })
  default     = null
  description = <<-EOT
    Per-invocation ceilings. Null takes the account defaults.

      - cpu_ms     : CPU milliseconds one invocation may burn. A cap turns a
                     runaway loop into a failed request instead of a bill.
      - subrequests: outbound fetches one invocation may make.

    These cap the Worker's own consumption, not what it is allowed to reach. They
    are a cost and blast-radius control, not a security control.
  EOT

  validation {
    condition     = var.limits == null || try(var.limits.cpu_ms, null) == null || try(var.limits.cpu_ms, 1) >= 1
    error_message = "limits.cpu_ms, when set, must be at least 1."
  }

  validation {
    condition     = var.limits == null || try(var.limits.subrequests, null) == null || try(var.limits.subrequests, 1) >= 1
    error_message = "limits.subrequests, when set, must be at least 1."
  }
}

variable "logpush" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether the Worker's logs are pushed to a configured Logpush job.

    Off by default because it does nothing on its own: the destination is a
    Logpush job defined outside this module, and turning this on without one just
    reads in the dashboard as though logs are being shipped somewhere.
  EOT
}

variable "observability" {
  type = object({
    enabled            = optional(bool, true)
    head_sampling_rate = optional(number)
    logs_enabled       = optional(bool, true)
    invocation_logs    = optional(bool, true)
  })
  default     = {}
  description = <<-EOT
    Workers Logs - Cloudflare's built-in, queryable log store for the Worker.

      - enabled           : master switch. On by default, because a Worker in the
                            request path with no logs cannot be debugged after the
                            fact, and the setting cannot be applied retroactively
                            to the requests you needed.
      - head_sampling_rate: fraction of requests recorded, 0 to 1. Null means all
                            of them. Sample a high-volume Worker rather than
                            turning logging off.
      - logs_enabled      : `console.log` output from the script.
      - invocation_logs   : one record per request - status, duration, outcome -
                            independent of anything the script prints. This is
                            what answers "did it even run".
  EOT

  validation {
    condition = (
      var.observability.head_sampling_rate == null ||
      (coalesce(var.observability.head_sampling_rate, 1) >= 0 && coalesce(var.observability.head_sampling_rate, 1) <= 1)
    )
    error_message = "observability.head_sampling_rate must be between 0 and 1, where 1 is every request."
  }
}

variable "tail_consumers" {
  type = list(object({
    service     = string
    environment = optional(string)
    namespace   = optional(string)
  }))
  default     = []
  description = <<-EOT
    Other Workers that receive this Worker's execution events as they happen, for
    shipping logs somewhere of your own.

      - service    : name of the consuming Worker.
      - environment: its environment, where it uses one.
      - namespace  : its dispatch namespace, for a Worker for Platforms consumer.

    A tail consumer sees request URLs, headers and anything the script logged, so
    it inherits the sensitivity of the traffic. Point it at a Worker under the
    same control as this one.
  EOT

  validation {
    condition     = alltrue([for consumer in var.tail_consumers : can(regex("^[a-z0-9][a-z0-9_-]{0,62}$", consumer.service))])
    error_message = "Each tail_consumers[*].service must be a valid Worker name: 1-63 characters of lowercase letters, numbers, hyphens or underscores."
  }
}

# Bindings
variable "bindings" {
  type = list(object({
    name = string
    type = string

    # kv_namespace
    namespace_id = optional(string)

    # r2_bucket
    bucket_name  = optional(string)
    jurisdiction = optional(string)

    # plain_text / secret_text
    text = optional(string)

    # json
    json = optional(string)

    # service / durable_object_namespace
    service     = optional(string)
    entrypoint  = optional(string)
    environment = optional(string)
    class_name  = optional(string)
    script_name = optional(string)

    # d1 / hyperdrive
    database_id = optional(string)
    id          = optional(string)

    # queue / analytics_engine / vectorize / workflow / pipelines / mtls_certificate
    queue_name     = optional(string)
    dataset        = optional(string)
    index_name     = optional(string)
    workflow_name  = optional(string)
    pipeline       = optional(string)
    certificate_id = optional(string)

    # secrets_store_secret
    store_id    = optional(string)
    secret_name = optional(string)

    # ratelimit
    simple = optional(object({
      limit              = number
      period             = number
      mitigation_timeout = optional(number)
    }))
  }))
  default     = []
  description = <<-EOT
    What the Worker can reach. Each entry becomes one property on `env` inside the
    script, so `name = "REDIRECTS"` is read as `env.REDIRECTS`.

    Supported `type` values and the field each one needs:

      ai                       -
      analytics_engine         dataset
      assets                   -
      browser                  -
      d1                       database_id
      durable_object_namespace class_name (+ script_name if defined elsewhere)
      hyperdrive               id
      json                     json
      kv_namespace             namespace_id
      mtls_certificate         certificate_id
      pipelines                pipeline
      plain_text               text
      queue                    queue_name
      ratelimit                simple = { limit, period }
      r2_bucket                bucket_name (+ jurisdiction for a non-default one)
      secret_text              text
      secrets_store_secret     store_id, secret_name
      service                  service (+ entrypoint, environment)
      vectorize                index_name
      version_metadata         -
      workflow                 workflow_name

    SECURITY: `secret_text` puts the literal value in Terraform state and in the
    variable file it came from. Use `secrets_store_secret`, which binds a
    reference into Cloudflare Secrets Store and keeps the value out of both. The
    layer calling this module gates `secret_text` behind an explicit opt-in for
    that reason.

    A binding is a capability, not a hint: anything the Worker can reach through
    `env`, any code path in the Worker can reach. Bind the one namespace or bucket
    it needs rather than the account's.
  EOT

  validation {
    condition     = alltrue([for binding in var.bindings : can(regex("^[A-Za-z_$][A-Za-z0-9_$]*$", binding.name))])
    error_message = "Each bindings[*].name must be a valid JavaScript identifier - letters, numbers, underscore or dollar, not starting with a digit. It is dereferenced as env.NAME inside the Worker."
  }

  validation {
    condition     = length(distinct([for binding in var.bindings : binding.name])) == length(var.bindings)
    error_message = "bindings[*].name must be unique within a Worker. Two entries with one name means the second silently wins and the first resource is unreachable from the script."
  }

  validation {
    condition = alltrue([
      for binding in var.bindings : contains([
        "ai", "analytics_engine", "assets", "browser", "d1", "durable_object_namespace",
        "hyperdrive", "json", "kv_namespace", "mtls_certificate", "pipelines", "plain_text",
        "queue", "ratelimit", "r2_bucket", "secret_text", "secrets_store_secret", "service",
        "vectorize", "version_metadata", "workflow",
      ], binding.type)
    ])
    error_message = "Each bindings[*].type must be one of: ai, analytics_engine, assets, browser, d1, durable_object_namespace, hyperdrive, json, kv_namespace, mtls_certificate, pipelines, plain_text, queue, ratelimit, r2_bucket, secret_text, secrets_store_secret, service, vectorize, version_metadata, workflow."
  }

  # One check per required field rather than one combined check, so the message
  # names the field that is missing instead of the whole table above.
  validation {
    condition     = alltrue([for binding in var.bindings : binding.type != "kv_namespace" || binding.namespace_id != null])
    error_message = "A kv_namespace binding needs namespace_id. Pass the namespace's ID, not its title - Cloudflare resolves bindings by ID."
  }

  validation {
    condition     = alltrue([for binding in var.bindings : binding.type != "r2_bucket" || binding.bucket_name != null])
    error_message = "An r2_bucket binding needs bucket_name."
  }

  validation {
    condition     = alltrue([for binding in var.bindings : !contains(["plain_text", "secret_text"], binding.type) || binding.text != null])
    error_message = "A plain_text or secret_text binding needs text."
  }

  validation {
    condition     = alltrue([for binding in var.bindings : binding.type != "json" || binding.json != null])
    error_message = "A json binding needs json, as a JSON-encoded string. Use jsonencode() on the value rather than hand-writing it."
  }

  validation {
    condition     = alltrue([for binding in var.bindings : binding.type != "json" || can(jsondecode(coalesce(binding.json, "null")))])
    error_message = "A json binding's json is not valid JSON. Cloudflare rejects the upload."
  }

  validation {
    condition     = alltrue([for binding in var.bindings : binding.type != "service" || binding.service != null])
    error_message = "A service binding needs service - the name of the Worker being called."
  }

  validation {
    condition     = alltrue([for binding in var.bindings : binding.type != "d1" || binding.database_id != null])
    error_message = "A d1 binding needs database_id."
  }

  validation {
    condition     = alltrue([for binding in var.bindings : binding.type != "hyperdrive" || binding.id != null])
    error_message = "A hyperdrive binding needs id."
  }

  validation {
    condition     = alltrue([for binding in var.bindings : binding.type != "queue" || binding.queue_name != null])
    error_message = "A queue binding needs queue_name."
  }

  validation {
    condition     = alltrue([for binding in var.bindings : binding.type != "analytics_engine" || binding.dataset != null])
    error_message = "An analytics_engine binding needs dataset."
  }

  validation {
    condition     = alltrue([for binding in var.bindings : binding.type != "vectorize" || binding.index_name != null])
    error_message = "A vectorize binding needs index_name."
  }

  validation {
    condition     = alltrue([for binding in var.bindings : binding.type != "workflow" || binding.workflow_name != null])
    error_message = "A workflow binding needs workflow_name."
  }

  validation {
    condition     = alltrue([for binding in var.bindings : binding.type != "pipelines" || binding.pipeline != null])
    error_message = "A pipelines binding needs pipeline."
  }

  validation {
    condition     = alltrue([for binding in var.bindings : binding.type != "mtls_certificate" || binding.certificate_id != null])
    error_message = "An mtls_certificate binding needs certificate_id."
  }

  validation {
    condition     = alltrue([for binding in var.bindings : binding.type != "durable_object_namespace" || binding.class_name != null])
    error_message = "A durable_object_namespace binding needs class_name, and script_name as well when the class lives in another Worker."
  }

  validation {
    condition = alltrue([
      for binding in var.bindings :
      binding.type != "secrets_store_secret" || (binding.store_id != null && binding.secret_name != null)
    ])
    error_message = "A secrets_store_secret binding needs both store_id and secret_name. The secret's value is never passed through Terraform, which is the point of using it."
  }

  validation {
    condition     = alltrue([for binding in var.bindings : binding.type != "ratelimit" || binding.simple != null])
    error_message = "A ratelimit binding needs simple = { limit, period }."
  }

  validation {
    condition = alltrue([
      for binding in var.bindings :
      binding.type != "r2_bucket" || binding.jurisdiction == null ||
      contains(["eu", "fedramp", "fedramp-high"], coalesce(binding.jurisdiction, "eu"))
    ])
    error_message = "An r2_bucket binding's jurisdiction must be null (default), \"eu\", \"fedramp\" or \"fedramp-high\", and must match the jurisdiction the bucket was created in - otherwise the binding addresses a differently-jurisdictioned bucket of the same name."
  }
}

# Triggers
variable "routes" {
  type = list(object({
    pattern = string
    zone_id = string
  }))
  default     = []
  description = <<-EOT
    URL patterns that send matching requests to this Worker.

      - pattern: `hostname/path*` form, e.g. "www.example.com/*". A route with no
                 path matches nothing useful; Cloudflare wants the trailing "/*"
                 to mean "the whole site".
      - zone_id: the zone the pattern's hostname belongs to.

    A route intercepts traffic before it reaches the origin, so a broken Worker on
    an apex route takes the site down rather than degrading it. Nothing here
    creates DNS: the hostname must already resolve through Cloudflare and be
    proxied, or the route never fires.
  EOT

  validation {
    condition     = alltrue([for route in var.routes : length(trimspace(route.pattern)) > 0])
    error_message = "Each routes[*].pattern must be non-empty."
  }

  validation {
    condition     = alltrue([for route in var.routes : !can(regex("^https?://", lower(route.pattern)))])
    error_message = "A routes[*].pattern includes a scheme. Cloudflare matches on host and path only, so write \"www.example.com/*\" rather than \"https://www.example.com/*\"."
  }

  validation {
    condition     = length(distinct([for route in var.routes : lower(route.pattern)])) == length(var.routes)
    error_message = "routes[*].pattern must be unique within a Worker."
  }
}

variable "custom_domains" {
  type = list(object({
    hostname  = string
    zone_id   = optional(string)
    zone_name = optional(string)
  }))
  default     = []
  description = <<-EOT
    Hostnames served entirely by this Worker, with Cloudflare creating the DNS
    record and the certificate.

      - hostname : the zone apex or a subdomain of it.
      - zone_id  : the zone containing the hostname.
      - zone_name: the zone's name, where Cloudflare asks for it by name.

    A custom domain differs from a route in what happens when the Worker does not
    answer: a route falls through to the origin, a custom domain has no origin to
    fall through to. It is the right shape for something that IS the Worker - an
    API, a redirect front door - and the wrong shape for a Worker that decorates
    an existing site.

    The hostname must not also be declared as a DNS record in the zones layer.
    Cloudflare writes that record itself, and two owners means a fight per apply.
  EOT

  validation {
    condition = alltrue([
      for domain in var.custom_domains :
      can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,}$", lower(domain.hostname)))
    ])
    error_message = "Each custom_domains[*].hostname must be a fully-qualified, lowercase hostname (e.g. api.example.com) with no scheme, port or path."
  }

  validation {
    condition     = length(distinct([for domain in var.custom_domains : lower(domain.hostname)])) == length(var.custom_domains)
    error_message = "custom_domains[*].hostname must be unique within a Worker."
  }

  validation {
    condition     = alltrue([for domain in var.custom_domains : domain.zone_id != null || domain.zone_name != null])
    error_message = "Each custom_domains entry needs zone_id or zone_name so Cloudflare knows which zone to write the record in."
  }
}

variable "cron_schedules" {
  type        = list(string)
  default     = []
  description = <<-EOT
    Cron expressions that invoke the Worker's `scheduled` handler. Five fields,
    UTC, e.g. "*/30 * * * *".

    A Worker with a schedule and no `scheduled` export runs and fails silently on
    every tick - there is no request to return an error to. Cloudflare also caps
    the number of triggers per Worker, so a long list here is a sign the schedule
    belongs inside one handler.
  EOT

  validation {
    condition     = alltrue([for schedule in var.cron_schedules : length(split(" ", join(" ", compact(split(" ", trimspace(schedule)))))) == 5])
    error_message = "Each cron_schedules entry must have five whitespace-separated fields: minute hour day-of-month month day-of-week."
  }

  validation {
    condition     = length(distinct(var.cron_schedules)) == length(var.cron_schedules)
    error_message = "cron_schedules must not repeat an expression."
  }
}
