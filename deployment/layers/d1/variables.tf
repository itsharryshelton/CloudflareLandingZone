# Layer d1 - inputs.
#
# D1 databases and their schema migrations. Holds its own state, so an apply of
# the workers layer - which redeploys scripts far more often than a database
# changes - never has a database in its plan.
#
# Config files:
#   accounts/<account>/account.tfvars - the account ID, shared with every layer
#   accounts/<account>/d1.tfvars      - the database inventory, shared with the
#                                       workers layer, which resolves a binding's
#                                       d1_database_key against it by name
#   accounts/<account>/tags.tfvars    - resource tags, shared with every layer
#                                       that tags
#
# d1.tfvars must assign `d1_databases` and nothing else. The pipeline passes a
# file to a layer only when that layer declares every variable in it, so a
# d1-only setting added there would stop the file reaching the workers layer,
# and every d1 binding would fail its plan. Put an account's override of a
# default or guardrail below in a file of its own, such as d1_settings.tfvars.
#
# Schema lives in this directory under `migrations/`, not in an account tree: it
# is code, it is customer-agnostic, and it belongs where it can be reviewed as
# code.

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare Account ID this layer run targets. D1 databases are account-scoped and reachable from any Worker in the account that binds them."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "d1_databases" {
  description = <<-EOT
    D1 databases, keyed by a logical key. A Worker binding in the workers layer
    refers to a database by that key, so no account tree ever carries a
    database UUID.

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
    Terraform owns the database; the tables inside it belong to the application.
    A migration is an ordered, one-way change that has to be applied in
    sequence, which is not what a plan reconciling desired state does.

    Migrations are committed to this layer, in a directory named for the same key
    used here:

      layers/d1/migrations/<key>/0001_initial_schema.sql

    .github/scripts/d1-migrations.sh applies them after every apply, against the
    ID this layer outputs. See layers/d1/migrations/README.md.

    EXISTING DATABASES ARE ADOPTED, NOT DUPLICATED
    A database that already exists under `name` - created with wrangler, in the
    dashboard, or by the workers layer before D1 had a layer of its own - is
    imported by the next plan rather than created again (see imports.tf). Its
    jurisdiction must match the one declared here, or the plan fails rather than
    replacing it.

    NAME AND JURISDICTION ARE REPLACE-ON-CHANGE
    Cloudflare fixes both when the database is created. Editing either destroys
    the database and creates another, and a destroyed D1 database takes every
    row with it - there is no snapshot and no undo. A plan that proposes
    replacing a database is a plan to lose its data; read it as such and export
    first. The location hint is the exception: a change to it after creation is
    ignored, because it moves nothing.

    Renaming a key here destroys and recreates the database, for the same
    reason, and orphans its migrations directory.
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
    error_message = "d1_databases keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses, state keys and migrations directory names."
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
    zerotrust, r2, workers and d1 - and each reads `defaults`, `allowed_values`
    and its own section, ignoring the rest. Declared in full everywhere because
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

    This layer reads `d1_databases`. Later wins: defaults, then
    <type>.defaults, then <type>.resources[key]. A null value drops a key an
    earlier level set. `managed-by` and `layer` are set by the layer itself and
    rejected here.

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
