# Layer pages - inputs.
#
# Cloudflare Pages projects: static and Jamstack front ends, built from Git or
# deployed by Direct Upload, with their bindings and custom domains.
#
# It declares projects. It does not deploy a build, and it does not write the
# Access application that protects one - see outputs.tf for the hand-over.
#
# Config files:
#   accounts/<account>/account.tfvars - the account ID, shared with every layer
#   accounts/<account>/zones.tfvars   - the zone inventory, for custom domains
#   accounts/<account>/pages.tfvars   - the projects
#
# Secrets, never in a file:
#   TF_VAR_pages_project_secrets      - encrypted env vars, per project and environment

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare Account ID this layer run targets. Pages projects are account-scoped."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "zones" {
  description = <<-EOT
    Zone inventory: logical key => domain name. The same file the zones layer is
    given, so the keys mean the same thing in both.

    This layer does not create zones. It looks up only the zones a custom domain
    actually references, to get their IDs (see zone_lookup.tf), which keeps the
    two layers' states independent.

    - `domain_name` - The apex domain (e.g. example.com).
    - `zone_tier`   - (Optional) Unused here, and declared only so that the shared
                      inventory file can carry it for the layers that do gate on
                      it. Terraform rejects a .tfvars attribute the variable type
                      does not declare.
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

variable "pages_projects" {
  description = <<-EOT
    Pages projects, keyed by a logical key. The key is the state address and
    what the outputs are keyed by.

    - `name`              - Project name and requested pages.dev subdomain. FIXED AT
                            CREATION: a change replaces the project, discards every
                            deployment and issues a new pages.dev hostname. If the name
                            is taken elsewhere on pages.dev, Cloudflare adds a random
                            suffix - read the real hostname from pages_projects.
    - `production_branch` - (Optional) Falls back to var.default_production_branch.
    - `source`            - (Optional) Git integration. Omit for Direct Upload, where
                            deployments come from `wrangler pages deploy` elsewhere.
                              type                           - github | gitlab
                              owner, repo_name               - the repository. Cloudflare's
                                                               Git app must already be
                                                               installed with access to it.
                              production_deployments_enabled - (Optional, default true)
                              pr_comments_enabled            - (Optional, default true)
                              preview_deployment_setting     - (Optional) all | none | custom.
                                                               Falls back to
                                                               var.default_preview_deployment_setting.
                              preview_branch_includes/excludes - (Optional) with "custom" only
                              path_includes/excludes         - (Optional)
    - `build`             - (Optional) Git projects only: build_command, destination_dir,
                            root_dir, build_caching.
    - `production`        - (Optional) Runtime configuration for production deploys.
    - `preview`           - (Optional) The same, for previews. NOT inherited from
                            production: a preview is built from any branch, so it gets
                            nothing it is not given here.
                            Both take:
                              compatibility_date, compatibility_flags,
                              always_use_latest_compatibility_date, fail_open,
                              placement_mode ("smart")
                              env_vars        - plain name => value. Readable in the
                                                dashboard and this layer's plan.
                              secret_names    - names whose values arrive in
                                                TF_VAR_pages_project_secrets.
                              kv_namespaces   - binding => namespace ID
                              d1_databases    - binding => database UUID
                              r2_buckets      - binding => { name, jurisdiction }
                              services        - binding => { service, environment, entrypoint }
                              queue_producers - binding => queue name
                            IDs are pasted from the workers and r2 layers' outputs;
                            this layer reads neither state.
    - `custom_domains`    - (Optional) Hostnames served by production. Each is:
                              hostname - FQDN, lowercase ASCII
                              zone_key - (Optional) a key in var.zones. Set, and this layer
                                         writes the proxied CNAME. Omitted, the record must
                                         exist elsewhere - gated by
                                         var.allow_unmanaged_pages_hostnames.
    - `access_protection` - (Optional) none | previews | all. Falls back to
                            var.default_access_protection. Decides which hostnames
                            appear in pages_access_applications. This layer does not
                            enforce it - the zerotrust layer does, once the entry is
                            copied there.

    BUILD-TIME VARIABLES CAN END UP IN THE BROWSER
    env_vars and secrets are available to the build as well as to Functions. A
    framework that inlines variables with a public prefix (VITE_, NEXT_PUBLIC_,
    PUBLIC_, REACT_APP_, ...) writes the value into the JavaScript every visitor
    downloads. The plan refuses a secret under such a name, and refuses a plain
    variable whose name looks like a credential unless
    var.allow_credential_like_plain_env_vars is set.
  EOT

  type = map(object({
    name              = string
    production_branch = optional(string)
    source = optional(object({
      type                           = string
      owner                          = string
      repo_name                      = string
      production_deployments_enabled = optional(bool, true)
      pr_comments_enabled            = optional(bool, true)
      preview_deployment_setting     = optional(string)
      preview_branch_includes        = optional(list(string), [])
      preview_branch_excludes        = optional(list(string), [])
      path_includes                  = optional(list(string), [])
      path_excludes                  = optional(list(string), [])
    }))
    build = optional(object({
      build_command   = optional(string)
      destination_dir = optional(string)
      root_dir        = optional(string)
      build_caching   = optional(bool)
    }))
    production = optional(object({
      compatibility_date                   = optional(string)
      compatibility_flags                  = optional(list(string), [])
      always_use_latest_compatibility_date = optional(bool)
      fail_open                            = optional(bool)
      placement_mode                       = optional(string)
      env_vars                             = optional(map(string), {})
      secret_names                         = optional(list(string), [])
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
      secret_names                         = optional(list(string), [])
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
    custom_domains = optional(list(object({
      hostname = string
      zone_key = optional(string)
    })), [])
    access_protection = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.pages_projects) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "pages_projects keys must be lowercase alphanumeric with underscores. The key is a state address - renaming one destroys the project and every deployment in it."
  }

  validation {
    condition     = alltrue([for p in var.pages_projects : p.access_protection == null || contains(["none", "previews", "all"], coalesce(p.access_protection, "none"))])
    error_message = "access_protection must be one of: none, previews, all."
  }
}

variable "pages_project_secrets" {
  type = map(object({
    production = optional(map(string), {})
    preview    = optional(map(string), {})
  }))
  default     = {}
  sensitive   = true
  description = <<-EOT
    Encrypted env vars, keyed by project key, then environment, then name. Every
    name here must be listed in that environment's `secret_names`, and every
    listed name must be here - the plan fails either way.

    THIS VARIABLE IS NEVER SET FROM A FILE. It arrives from the pipeline as
    TF_VAR_pages_project_secrets, mapped in _terraform-run.yml from the
    <account>-plan environment's TF_VAR_PAGES_PROJECT_SECRETS secret - the plan
    environment, not the apply one, because apply runs a saved plan file and
    never re-reads TF_VAR_:

      TF_VAR_pages_project_secrets={"admin_portal":{"production":{"SESSION_SECRET":"<value>"}}}

    Cloudflare never returns the value once set. Terraform keeps it in this
    layer's state in plain text regardless.
  EOT
}

variable "default_production_branch" {
  type        = string
  description = "Production branch for a project that does not state one. Set in defaults.auto.tfvars."
}

variable "default_preview_deployment_setting" {
  type        = string
  description = "Preview deployment setting for a Git project that does not state one. Set in defaults.auto.tfvars."

  validation {
    condition     = contains(["all", "none", "custom"], var.default_preview_deployment_setting)
    error_message = "default_preview_deployment_setting must be one of: all, none, custom."
  }
}

variable "default_access_protection" {
  type        = string
  description = "Access protection for a project that does not state one. Set in defaults.auto.tfvars."

  validation {
    condition     = contains(["none", "previews", "all"], var.default_access_protection)
    error_message = "default_access_protection must be one of: none, previews, all."
  }
}

variable "allow_unprotected_previews" {
  type        = bool
  description = "Whether a project may publish previews with access_protection = \"none\". Set in defaults.auto.tfvars."
}

variable "allow_unmanaged_pages_hostnames" {
  type        = bool
  description = "Whether a custom domain may omit zone_key, leaving its CNAME to be created elsewhere. Set in defaults.auto.tfvars."
}

variable "allow_credential_like_plain_env_vars" {
  type        = bool
  description = "Whether a plain env var may have a name that looks like a credential (SECRET, TOKEN, PASSWORD, API_KEY, ...). Set in defaults.auto.tfvars."
}
