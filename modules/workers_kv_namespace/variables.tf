variable "account_id" {
  type        = string
  description = "Cloudflare Account ID. Workers KV namespaces are account-scoped, and a namespace is reachable from any Worker in the account that binds it."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "title" {
  type        = string
  description = <<-EOT
    Human-readable name for the namespace, as it appears in the dashboard.

    Cloudflare identifies a namespace by an opaque ID rather than by this string,
    so renaming is safe and keeps every key. Two namespaces may share a title,
    which is exactly how an account ends up with three "redirects" nobody can tell
    apart - include the environment or the brand in the name.
  EOT

  validation {
    condition     = length(trimspace(var.title)) > 0 && length(var.title) <= 512
    error_message = "title must be a non-empty string of at most 512 characters."
  }
}

variable "pairs" {
  type = map(object({
    value    = string
    metadata = optional(string)
  }))
  default     = {}
  description = <<-EOT
    Key/value pairs Terraform owns, keyed by the KV key name. Every pair becomes
    one resource in state, and removing an entry deletes the key from Cloudflare.

      - value   : the stored bytes, as a string. Binary belongs elsewhere; write
                  base64 yourself if you must, and have the Worker decode it.
      - metadata: optional JSON string stored alongside the value and returned by
                  `getWithMetadata()` without a second read.

    This is for small, configuration-shaped data - a feature flag map, a handful
    of routing overrides, a maintenance switch - where the value belongs in a pull
    request next to the Worker that reads it.

    It is NOT how a bulk dataset gets loaded. Terraform issues one API call per
    key, keeps every value in state, and re-plans all of them on every run, so a
    redirect table of tens of thousands of rows takes hours and produces a state
    file nobody can review. `max_managed_pairs` exists to stop that arriving by
    accident; see its description for what to do instead.

    SECURITY: values are stored in Terraform state in plain text and appear in
    plan output. Nothing secret goes in here - a Worker reads secrets from a
    `secrets_store_secret` binding, not from KV.
  EOT

  validation {
    condition     = alltrue([for key in keys(var.pairs) : length(key) > 0 && length(key) <= 512])
    error_message = "Each pairs key must be 1-512 bytes. Cloudflare rejects a longer key name."
  }

  validation {
    condition     = alltrue([for key in keys(var.pairs) : key == trimspace(key)])
    error_message = "A pairs key has leading or trailing whitespace. KV keys are compared byte for byte, so the Worker would never find it."
  }

  validation {
    condition     = alltrue([for pair in values(var.pairs) : pair.metadata == null || can(jsondecode(coalesce(pair.metadata, "{}")))])
    error_message = "Each pairs[*].metadata, when set, must be a JSON document. Cloudflare rejects anything else."
  }
}

variable "max_managed_pairs" {
  type        = number
  default     = 500
  description = <<-EOT
    Ceiling on how many `pairs` this module will manage, asserted before anything
    is created.

    The limit is about Terraform rather than about KV: KV itself is happy with
    billions of keys, but each one managed here is a resource in state, a line in
    every plan and a separate API call on every apply. A few hundred is
    configuration; tens of thousands is a dataset, and a dataset should be written
    by the system that owns it - `wrangler kv bulk put` from the pipeline, or the
    application at runtime - with Terraform owning only the namespace and the
    bindings.

    Raise it deliberately, on a pull request that says why, rather than because a
    plan failed.
  EOT

  validation {
    condition     = var.max_managed_pairs >= 0
    error_message = "max_managed_pairs must be zero or greater."
  }
}
