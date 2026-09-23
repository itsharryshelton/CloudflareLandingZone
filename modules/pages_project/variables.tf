variable "account_id" {
  type        = string
  description = "Cloudflare Account ID. A Pages project is account-scoped; its custom domains may sit on any zone, but only a zone on this account can have its CNAME managed here."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "name" {
  type        = string
  description = <<-EOT
    Project name. It is also the requested pages.dev subdomain, so it is
    FIXED AT CREATION: changing it replaces the project, which discards every
    deployment and issues a new pages.dev hostname.

    Requested, not guaranteed. pages.dev is one namespace shared by every
    Cloudflare account, and a name already taken there is given a random suffix.
    Read the real hostname from the `project.subdomain` output; never build it
    from this value.
  EOT

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,56}[a-z0-9])?$", var.name))
    error_message = "name must be 1-58 characters of lowercase letters, digits and hyphens, and may not start or end with a hyphen. It becomes a DNS label under pages.dev."
  }
}

variable "production_branch" {
  type        = string
  description = "The branch whose deployments are production. Every other branch deploys as a preview."

  validation {
    condition     = trimspace(var.production_branch) != ""
    error_message = "production_branch must not be empty."
  }
}

# Not called `source`: that is a meta-argument on every module block, so a
# variable of that name could never be set by a caller.
variable "git_source" {
  type = object({
    type                           = string
    owner                          = string
    repo_name                      = string
    production_deployments_enabled = optional(bool, true)
    pr_comments_enabled            = optional(bool, true)
    preview_deployment_setting     = optional(string, "all")
    preview_branch_includes        = optional(list(string), [])
    preview_branch_excludes        = optional(list(string), [])
    path_includes                  = optional(list(string), [])
    path_excludes                  = optional(list(string), [])
  })
  default     = null
  description = <<-EOT
    Git integration. Null means a Direct Upload project: nothing builds on
    Cloudflare, and deployments arrive from `wrangler pages deploy` in some
    other pipeline.

    - `type`                           - github | gitlab.
    - `owner` / `repo_name`            - The repository. Cloudflare's GitHub or GitLab
                                         app must already be installed on the owner with
                                         access to it, or creating the project fails -
                                         Terraform cannot install it.
    - `production_deployments_enabled` - (Optional, default true) Deploy on every push
                                         to production_branch.
    - `pr_comments_enabled`            - (Optional, default true) Comment the preview
                                         URL on pull requests.
    - `preview_deployment_setting`     - (Optional, default "all") all | none | custom.
                                         Every preview is published on a pages.dev
                                         hostname that is public unless Access covers it.
    - `preview_branch_includes/excludes` - (Optional) Only with "custom".
    - `path_includes/excludes`         - (Optional) Only deploy when these paths change.

    FIXED AT CREATION in practice: moving between Direct Upload and a Git source,
    or between repositories, is not something Cloudflare changes in place.
  EOT

  validation {
    condition     = var.git_source == null || contains(["github", "gitlab"], try(var.git_source.type, ""))
    error_message = "git_source.type must be github or gitlab."
  }

  validation {
    condition     = var.git_source == null || contains(["all", "none", "custom"], try(var.git_source.preview_deployment_setting, ""))
    error_message = "git_source.preview_deployment_setting must be one of: all, none, custom."
  }

  validation {
    condition = var.git_source == null || try(var.git_source.preview_deployment_setting, "") == "custom" || (
      length(try(var.git_source.preview_branch_includes, [])) == 0 && length(try(var.git_source.preview_branch_excludes, [])) == 0
    )
    error_message = "preview_branch_includes and preview_branch_excludes are only read when preview_deployment_setting = \"custom\". Set anywhere else they are silently ignored, so the branch filter that looks configured is not."
  }
}

variable "build_config" {
  type = object({
    build_command   = optional(string)
    destination_dir = optional(string)
    root_dir        = optional(string)
    build_caching   = optional(bool)
  })
  default     = null
  description = "How Cloudflare builds a Git-sourced project. Ignored by a Direct Upload project, which arrives already built."
}

variable "deployment_configs" {
  description = <<-EOT
    Per-environment runtime configuration, for `production` and `preview`. The
    two are separate on purpose: a preview built from any branch should not be
    handed production's bindings or secrets by default.

    - `compatibility_date` / `compatibility_flags` - Pages Functions runtime.
    - `always_use_latest_compatibility_date`       - (Optional) Track the latest date.
    - `fail_open`       - (Optional) Serve static assets when a Function fails. Leave
                          it off for anything behind a Function-based auth check.
    - `placement_mode`  - (Optional) "smart" to run Functions near their backend.
    - `env_vars`        - Plain-text variables, name => value. Visible in the
                          dashboard, the API and this layer's plan. NOT for secrets.
    - `kv_namespaces`   - Binding name => KV namespace ID.
    - `d1_databases`    - Binding name => D1 database UUID.
    - `r2_buckets`      - Binding name => { name, jurisdiction }.
    - `services`        - Binding name => { service, environment, entrypoint }.
    - `queue_producers` - Binding name => queue name.

    Secrets are not taken here - see var.secret_env_vars.
  EOT

  type = object({
    production = optional(object({
      compatibility_date                   = optional(string)
      compatibility_flags                  = optional(list(string), [])
      always_use_latest_compatibility_date = optional(bool)
      fail_open                            = optional(bool)
      placement_mode                       = optional(string)
      env_vars                             = optional(map(string), {})
      kv_namespaces                        = optional(map(string), {})
      d1_databases                         = optional(map(string), {})
      r2_buckets = optional(map(object({
        name         = string
        jurisdiction = optional(string)
      })), {})
      services = optional(map(object({
        service     = string
        environment = optional(string)
        entrypoint  = optional(string)
      })), {})
      queue_producers = optional(map(string), {})
    }), {})
    preview = optional(object({
      compatibility_date                   = optional(string)
      compatibility_flags                  = optional(list(string), [])
      always_use_latest_compatibility_date = optional(bool)
      fail_open                            = optional(bool)
      placement_mode                       = optional(string)
      env_vars                             = optional(map(string), {})
      kv_namespaces                        = optional(map(string), {})
      d1_databases                         = optional(map(string), {})
      r2_buckets = optional(map(object({
        name         = string
        jurisdiction = optional(string)
      })), {})
      services = optional(map(object({
        service     = string
        environment = optional(string)
        entrypoint  = optional(string)
      })), {})
      queue_producers = optional(map(string), {})
    }), {})
  })
  default = {}

  validation {
    condition = alltrue([
      for env in [var.deployment_configs.production, var.deployment_configs.preview] :
      env.compatibility_date == null || can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", coalesce(env.compatibility_date, "1970-01-01")))
    ])
    error_message = "compatibility_date must be YYYY-MM-DD."
  }

  validation {
    condition = alltrue([
      for env in [var.deployment_configs.production, var.deployment_configs.preview] :
      env.placement_mode == null || contains(["smart"], coalesce(env.placement_mode, "smart"))
    ])
    error_message = "placement_mode must be \"smart\", or left unset for default placement."
  }

  validation {
    condition = alltrue(flatten([
      for env in [var.deployment_configs.production, var.deployment_configs.preview] : [
        for name in concat(
          keys(env.env_vars), keys(env.kv_namespaces), keys(env.d1_databases),
          keys(env.r2_buckets), keys(env.services), keys(env.queue_producers),
        ) : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", name))
      ]
    ]))
    error_message = "Variable and binding names must be valid JavaScript identifiers: letters, digits and underscores, not starting with a digit. They are read as env.<NAME> inside a Function."
  }
}

variable "secret_env_vars" {
  type = object({
    production = optional(map(string), {})
    preview    = optional(map(string), {})
  })
  default     = {}
  sensitive   = true
  description = <<-EOT
    Encrypted variables, per environment, name => value. Sent as secret_text,
    so the dashboard and API never show the value again.

    Terraform still does. Every value here is in state in plain text, because
    Terraform records what it sent. The layer feeds this from a pipeline secret
    rather than a file for that reason; the state is the other copy.

    A secret is only secret at runtime. A build step that reads one into a
    framework's public prefix (VITE_, NEXT_PUBLIC_, PUBLIC_ and the like) ships
    it to every browser in the bundle.
  EOT
}

variable "custom_domains" {
  type = list(object({
    hostname = string
    zone_id  = optional(string)
  }))
  default     = []
  description = <<-EOT
    Custom hostnames served by the production deployment.

    - `hostname` - Fully qualified, lowercase, no scheme, port, path or wildcard.
    - `zone_id`  - (Optional) The zone the hostname is in. Set, and this module
                   writes the proxied CNAME to the project's pages.dev hostname.
                   Null, and the record must be created somewhere else - Cloudflare
                   does not create it when the domain is added through the API,
                   so without it the domain sits at "pending" and never serves.

    The hostname must not also be declared as a DNS record in the dns layer.

    ASCII only. Punycode (xn--) is accepted; whether the Pages API normalises a
    Unicode hostname the way the zones API does has not been verified, and a
    hostname that reads back differently from what was sent forces a
    replacement on every plan.
  EOT

  validation {
    condition = alltrue([
      for domain in var.custom_domains :
      can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z][a-z0-9-]{0,61}[a-z0-9]$", domain.hostname))
    ])
    error_message = "Each custom_domains[*].hostname must be a fully qualified, lowercase ASCII hostname (e.g. www.example.com, punycode allowed) with no scheme, port, path or wildcard."
  }

  validation {
    condition     = length(distinct([for domain in var.custom_domains : domain.hostname])) == length(var.custom_domains)
    error_message = "custom_domains[*].hostname must be unique within a project."
  }

  validation {
    condition     = alltrue([for domain in var.custom_domains : domain.zone_id == null || can(regex("^[0-9a-f]{32}$", coalesce(domain.zone_id, "")))])
    error_message = "custom_domains[*].zone_id must be a 32-character hexadecimal zone identifier, or null."
  }
}
