variable "account_id" {
  type        = string
  default     = null
  description = <<-EOT
    Cloudflare Account ID, for an account-scoped job such as audit_logs or
    gateway_dns. Give exactly one of account_id and zone_id: each dataset is
    produced at one scope, and Cloudflare refuses it pushed from the other.
    Changing it replaces the job.
  EOT

  validation {
    condition     = var.account_id == null || can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id, when set, must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "zone_id" {
  type        = string
  default     = null
  description = <<-EOT
    Cloudflare Zone ID, for a zone-scoped job such as http_requests. Give exactly
    one of account_id and zone_id. Changing it replaces the job.
  EOT

  validation {
    condition     = var.zone_id == null || can(regex("^[0-9a-f]{32}$", var.zone_id))
    error_message = "zone_id, when set, must be a 32-character hexadecimal Cloudflare zone identifier."
  }
}

variable "name" {
  type        = string
  default     = null
  description = "Human-readable job name shown in the dashboard. A label, not identity: Cloudflare does not require it to be unique, and renaming updates the job in place."

  validation {
    condition     = var.name == null ? true : trimspace(var.name) != ""
    error_message = "name, when set, must not be empty. Leave it unset rather than blank."
  }
}

variable "dataset" {
  type        = string
  description = <<-EOT
    The log category to push, e.g. "http_requests", "firewall_events",
    "audit_logs" or "gateway_dns". Required here although the provider would
    default it to http_requests: a job whose dataset nobody chose pushes the
    wrong logs. Changing it replaces the job.
  EOT

  validation {
    condition     = can(regex("^[a-z0-9_]+$", var.dataset))
    error_message = "dataset must be a Cloudflare dataset identifier in snake_case, such as \"http_requests\" or \"audit_logs\"."
  }
}

variable "destination_conf" {
  type        = string
  sensitive   = true
  description = <<-EOT
    Where the logs go, as a destination URI with its parameters, e.g.
    "s3://<bucket>/<path>/{DATE}?region=eu-west-2&sse=AES256" or
    "r2://<bucket>/<path>/{DATE}?account-id=<id>&access-key-id=<key>&secret-access-key=<secret>".
    Cloudflare expands {DATE} into a daily prefix.

    Sensitive because many destinations carry their credential in the URI. The
    provider marks it sensitive too, so it never appears in a plan, and no
    output of this module returns it.
  EOT

  validation {
    condition     = can(regex("^[a-z][a-z0-9+.-]*://\\S+$", trimspace(var.destination_conf)))
    error_message = "destination_conf must be a destination URI with a scheme, such as \"s3://bucket/path/{DATE}?region=eu-west-2\". The value is not shown because it may carry a credential."
  }
}

variable "ownership_challenge" {
  type        = string
  default     = null
  sensitive   = true
  description = <<-EOT
    Token proving control of the destination, for destinations where Cloudflare
    asks for one before it will push - object stores such as S3 and Google Cloud
    Storage, where Cloudflare writes a challenge file into the bucket and the
    token is that file's contents. A destination that carries its own credential
    in destination_conf, R2 among them, does not need one. Checked when the job
    is created or its destination changes.
  EOT
}

variable "enabled" {
  type        = bool
  default     = true
  nullable    = false
  description = "Whether the job pushes. Defaults true here although the provider defaults it false: a job created disabled looks configured in the dashboard and ships nothing."
}

variable "filter" {
  type        = string
  default     = null
  description = <<-EOT
    Which events to push, as Cloudflare's filter JSON:
      {"where":{"and":[{"key":"ClientRequestHost","operator":"eq","value":"example.com"}]}}
    "and" and "or" nest; the operators are Cloudflare's (eq, !eq, contains, in,
    startsWith and the rest). Unset pushes every event. Re-serialised compactly
    before it is sent, so formatting in the caller never reads as drift.
  EOT

  validation {
    condition     = var.filter == null ? true : can(jsondecode(var.filter).where)
    error_message = "filter must be a JSON object with a top-level \"where\" key, e.g. {\"where\":{\"and\":[{\"key\":\"ClientRequestHost\",\"operator\":\"eq\",\"value\":\"example.com\"}]}}."
  }
}

variable "kind" {
  type        = string
  default     = ""
  nullable    = false
  description = "\"\" for a standard Logpush job, or \"edge\" for Edge Log Delivery, which Cloudflare offers for the zone-scoped http_requests dataset only."

  validation {
    condition     = contains(["", "edge"], var.kind)
    error_message = "kind must be \"\" (standard Logpush) or \"edge\" (Edge Log Delivery)."
  }
}

variable "max_upload_bytes" {
  type        = number
  default     = null
  description = "Largest uncompressed batch file, in bytes: 5000000 (5 MB) to 1000000000 (1 GB), or 0 for Cloudflare's per-destination default. Unset means 0."

  validation {
    condition = var.max_upload_bytes == null ? true : (
      floor(var.max_upload_bytes) == var.max_upload_bytes
      && (var.max_upload_bytes == 0 || (var.max_upload_bytes >= 5000000 && var.max_upload_bytes <= 1000000000))
    )
    error_message = "max_upload_bytes must be a whole number: 0, or between 5000000 and 1000000000."
  }
}

variable "max_upload_interval_seconds" {
  type        = number
  default     = null
  description = "Longest wait before a batch is pushed, in seconds: 30 to 300, or 0 for Cloudflare's per-destination default. Unset means 0."

  validation {
    condition = var.max_upload_interval_seconds == null ? true : (
      floor(var.max_upload_interval_seconds) == var.max_upload_interval_seconds
      && (var.max_upload_interval_seconds == 0 || (var.max_upload_interval_seconds >= 30 && var.max_upload_interval_seconds <= 300))
    )
    error_message = "max_upload_interval_seconds must be a whole number: 0, or between 30 and 300."
  }
}

variable "max_upload_records" {
  type        = number
  default     = null
  description = "Most log lines in one batch: 1000 to 1000000, or 0 for Cloudflare's default. Unset means 0."

  validation {
    condition = var.max_upload_records == null ? true : (
      floor(var.max_upload_records) == var.max_upload_records
      && (var.max_upload_records == 0 || (var.max_upload_records >= 1000 && var.max_upload_records <= 1000000))
    )
    error_message = "max_upload_records must be a whole number: 0, or between 1000 and 1000000."
  }
}

variable "output_options" {
  type = object({
    field_names       = optional(list(string))
    output_type       = optional(string)
    timestamp_format  = optional(string)
    sample_rate       = optional(number)
    cve_2021_44228    = optional(bool)
    merge_subrequests = optional(bool)
    batch_prefix      = optional(string)
    batch_suffix      = optional(string)
    field_delimiter   = optional(string)
    record_delimiter  = optional(string)
    record_prefix     = optional(string)
    record_suffix     = optional(string)
    record_template   = optional(string)
  })
  default     = null
  description = <<-EOT
    Shape of each record. Cloudflare replaces the whole object on every update,
    so an attribute left unset here returns to Cloudflare's default rather than
    keeping a value set in the dashboard.

      - field_names       : the fields to include. Cloudflare has no "all fields"
                            option; each dataset's page in the Logpush docs lists
                            its fields.
      - output_type       : "ndjson" (Cloudflare's default) or "csv".
      - timestamp_format  : "unixnano" (Cloudflare's default for API-created
                            jobs), "unix", "rfc3339", "rfc3339ms" or "rfc3339ns".
      - sample_rate       : fraction of events pushed, above 0 and up to 1.
      - cve_2021_44228    : rewrite every "$${" in the output to "x{", so a
                            Log4Shell lookup string a client sent never reaches a
                            downstream log processor intact.
      - merge_subrequests : fold subrequests into their parent request.
                            http_requests only.
      - batch_prefix, batch_suffix, field_delimiter, record_delimiter,
        record_prefix, record_suffix, record_template
                          : custom framing, as Cloudflare's log output options
                            document them.
  EOT

  validation {
    condition = try(var.output_options.field_names, null) == null ? true : (
      alltrue([for field in var.output_options.field_names : trimspace(field) != ""])
      && length(distinct(var.output_options.field_names)) == length(var.output_options.field_names)
    )
    error_message = "output_options.field_names must not contain an empty or repeated field name."
  }

  validation {
    condition     = contains(["ndjson", "csv"], coalesce(try(var.output_options.output_type, null), "ndjson"))
    error_message = "output_options.output_type must be \"ndjson\" or \"csv\"."
  }

  validation {
    condition     = contains(["unixnano", "unix", "rfc3339", "rfc3339ms", "rfc3339ns"], coalesce(try(var.output_options.timestamp_format, null), "unixnano"))
    error_message = "output_options.timestamp_format must be one of \"unixnano\", \"unix\", \"rfc3339\", \"rfc3339ms\" or \"rfc3339ns\"."
  }

  # Zero is excluded although the provider accepts it: a job sampling nothing
  # looks healthy in the dashboard and ships nothing.
  validation {
    condition = try(var.output_options.sample_rate, null) == null ? true : (
      var.output_options.sample_rate > 0 && var.output_options.sample_rate <= 1
    )
    error_message = "output_options.sample_rate must be above 0 and at most 1. 1 pushes every event."
  }
}
