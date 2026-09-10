# Layer logpush - inputs.
#
# Config files:
#   accounts/<account>/account.tfvars - the account ID, shared with every layer
#   accounts/<account>/zones.tfvars   - the zone inventory, for zone-scoped jobs
#   accounts/<account>/logpush.tfvars - Logpush jobs
#
# Never from a file - the pipeline supplies these from the <account>-plan
# environment:
#   TF_VAR_logpush_destination_secrets  - destinations that carry a credential
#   TF_VAR_logpush_ownership_challenges - destination ownership tokens

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare Account ID this layer run targets. Account-scoped jobs are created against it; zone-scoped jobs use it only to find their zone."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "zones" {
  description = <<-EOT
    Zone inventory: logical key => domain name. The same file the zones layer is
    given, so the keys mean the same thing in both.

    This layer does not create zones. It looks up only the zones a zone-scoped
    job references, to get their IDs (see zone_lookup.tf), which keeps the two
    layers' states independent.

    - `domain_name` - The apex domain (e.g. example.com).
    - `zone_tier`   - (Optional) The zone's Cloudflare rate plan. Defaults to
                      var.default_zone_tier. Read here because zone-scoped
                      Logpush is an Enterprise entitlement - see
                      var.logpush_min_zone_tier. This layer never changes a plan;
                      only the zones layer can do that.
  EOT
  type = map(object({
    domain_name = string
    zone_tier   = optional(string)
  }))

  validation {
    condition     = alltrue([for key in keys(var.zones) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "zones keys must be lowercase alphanumeric with underscores."
  }

  validation {
    condition = alltrue([
      for zone in var.zones : zone.zone_tier == null || contains([
        "free", "lite", "pro", "pro_plus", "business", "enterprise",
        "partners_free", "partners_pro", "partners_business",
        "partners_enterprise", "partners_ent",
      ], coalesce(zone.zone_tier, "free"))
    ])
    error_message = "zones[*].zone_tier must be one of: free, lite, pro, pro_plus, business, enterprise, partners_free, partners_pro, partners_business, partners_enterprise, partners_ent."
  }
}

variable "default_zone_tier" {
  type        = string
  default     = "free"
  description = "Rate plan assumed for a zone whose inventory entry does not name one. Must match what the zones layer was given, or the Enterprise gate here will not agree with the plan the zone is actually on."

  validation {
    condition = contains([
      "free", "lite", "pro", "pro_plus", "business", "enterprise",
      "partners_free", "partners_pro", "partners_business",
      "partners_enterprise", "partners_ent",
    ], var.default_zone_tier)
    error_message = "default_zone_tier must be one of: free, lite, pro, pro_plus, business, enterprise, partners_free, partners_pro, partners_business, partners_enterprise, partners_ent."
  }
}

variable "logpush_jobs" {
  description = <<-EOT
    Logpush jobs, keyed by a logical key. The key is identity: renaming it
    destroys the job and creates a new one, and nothing is backfilled for the
    events in between.

    - `dataset`          - The log category, e.g. "http_requests",
                           "firewall_events", "audit_logs", "gateway_dns". A zone
                           dataset needs `zone_key`; an account dataset must not
                           have one. See var.logpush_zone_datasets and
                           var.logpush_account_datasets. Changing it replaces the
                           job.
    - `zone_key`         - (Optional) A key from zones.tfvars, for a zone-scoped
                           job. Leave it out for an account-scoped one. The zone
                           must be on var.logpush_min_zone_tier or above.
    - `name`             - (Optional) Label in the dashboard. Not unique, not
                           identity.
    - `destination_conf` - (Optional) Where the logs go, for a destination with no
                           credential in its URI:
                             "s3://<bucket>/<path>/{DATE}?region=eu-west-2&sse=AES256"
                             "gs://<bucket>/<path>/{DATE}"
                           Leave it out for any destination that carries one - R2,
                           Splunk, Datadog, Azure, an HTTP endpoint with an auth
                           header - and supply the whole URI in
                           var.logpush_destination_secrets under this job's key.
                           Exactly one of the two per job. A credential-shaped
                           value here fails the plan.
    - `enabled`          - (Optional) Falls back to var.default_logpush_job_enabled.
    - `filter`           - (Optional) Cloudflare's filter JSON, selecting which
                           events to push. A heredoc keeps it readable:
                             filter = <<-JSON
                               {"where":{"and":[{"key":"ClientRequestHost","operator":"eq","value":"example.com"}]}}
                             JSON
                           Unset pushes every event.
    - `kind`             - (Optional) "" (default), or "edge" for Edge Log
                           Delivery, which is http_requests only.
    - `max_upload_bytes`, `max_upload_interval_seconds`, `max_upload_records`
                         - (Optional) Batch limits: 5 MB to 1 GB, 30 to 300
                           seconds, 1,000 to 1,000,000 records, or 0 for
                           Cloudflare's default. A shorter interval gets events to
                           a SIEM sooner, in more and smaller files.
    - `output_options`   - Record shape. `field_names` is required: Cloudflare has
                           no "all fields" option, and each dataset's page in the
                           Logpush docs lists its fields. `output_type`,
                           `timestamp_format` and `cve_2021_44228` fall back to the
                           platform defaults below. A `sample_rate` below 1 is
                           restricted - see var.allow_logpush_sampling.
                           `merge_subrequests`, `batch_*`, `record_*` and
                           `field_delimiter` as Cloudflare documents them.

    ENTERPRISE ONLY. On an account without Logpush, leave this map empty.
  EOT
  type = map(object({
    dataset                     = string
    zone_key                    = optional(string)
    name                        = optional(string)
    destination_conf            = optional(string)
    enabled                     = optional(bool)
    filter                      = optional(string)
    kind                        = optional(string, "")
    max_upload_bytes            = optional(number)
    max_upload_interval_seconds = optional(number)
    max_upload_records          = optional(number)
    output_options = object({
      field_names       = list(string)
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
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.logpush_jobs) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "logpush_jobs keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
  }

  validation {
    condition     = alltrue([for job in var.logpush_jobs : length(job.output_options.field_names) > 0])
    error_message = "Each logpush_jobs[*].output_options.field_names must list at least one field. Cloudflare has no \"all fields\" option; each dataset's page in the Logpush docs lists the fields it has."
  }
}

# Secrets. Never set from a file - see the header of this file.
variable "logpush_destination_secrets" {
  type        = map(string)
  default     = {}
  sensitive   = true
  description = <<-EOT
    Destinations that carry a credential, keyed by the same key as
    var.logpush_jobs: the job's whole destination_conf, credential included.

      r2://<bucket>/<path>/{DATE}?account-id=<id>&access-key-id=<key id>&secret-access-key=<secret>
      splunk://<endpoint>?channel=<channel id>&sourcetype=<type>&header_Authorization=<HEC token>
      datadog://<endpoint>?header_DD-API-KEY=<api key>&ddsource=cloudflare

    THIS VARIABLE IS NEVER SET FROM A FILE. It arrives from the pipeline as
    TF_VAR_logpush_destination_secrets, mapped in _terraform-run.yml from the
    <account>-plan environment's TF_VAR_LOGPUSH_DESTINATION_SECRETS secret - the
    plan environment, not the apply one, because apply runs a saved plan file
    and never re-reads TF_VAR_:

      TF_VAR_logpush_destination_secrets={"audit_archive":"r2://..."}

    A credential written into a .tfvars is committed the moment somebody runs
    `git add .`, and .gitignore will not save you: accounts/*/*.tfvars is
    explicitly un-ignored so account trees can be committed. The plan fails on a
    credential-shaped destination_conf in logpush.tfvars, but that is a
    backstop, not a control.

    The value reaches Terraform state and the saved plan in plain text, because
    Terraform records what it sent. Both are credential material. Scope each
    credential to the one bucket or index it writes to: an R2 token on the log
    bucket alone, a Splunk HEC token bound to one index.
  EOT
}

variable "logpush_ownership_challenges" {
  type        = map(string)
  default     = {}
  sensitive   = true
  description = <<-EOT
    Ownership challenge tokens, keyed by the same key as var.logpush_jobs, for
    destinations where Cloudflare asks for proof of control before it will push
    - object stores such as S3 and Google Cloud Storage. Cloudflare writes a
    challenge file into the destination (from the dashboard, or
    POST .../logpush/ownership with the destination_conf); the token is that
    file's contents. A destination carrying its own credential, R2 among them,
    needs none.

    Never set from a file, and supplied the same way as
    var.logpush_destination_secrets:

      TF_VAR_logpush_ownership_challenges={"primary_http_requests":"<token>"}

    Checked when a job is created or its destination changes. Leave the entry in
    place afterwards: removing it plans an in-place update that clears it.
  EOT
}

# Dataset catalogue. Which scope a dataset is produced at is a fact about
# Cloudflare, not a tenant choice, so it lives here rather than in an account
# tree. Extend it when Cloudflare adds a dataset the provider accepts.
variable "logpush_zone_datasets" {
  type        = list(string)
  description = "Datasets Cloudflare produces per zone. A job for one of these needs a zone_key. A dataset in both this list and var.logpush_account_datasets may be pushed from either scope."
  default = [
    "dns_logs",
    "firewall_events",
    "http_requests",
    "nel_reports",
    "page_shield_events",
    "spectrum_events",
    "websocket_analytics",
    "zaraz_events",
  ]
}

variable "logpush_account_datasets" {
  type        = list(string)
  description = "Datasets Cloudflare produces per account. A job for one of these must not name a zone_key. A dataset in both this list and var.logpush_zone_datasets may be pushed from either scope."
  default = [
    "access_requests",
    "audit_logs",
    "audit_logs_v2",
    "biso_user_actions",
    "casb_findings",
    "device_posture_results",
    "dex_application_tests",
    "dex_device_state_events",
    "dlp_forensic_copies",
    "dns_firewall_logs",
    "email_security_alerts",
    "email_security_post_delivery_events",
    "firewall_events",
    "gateway_dns",
    "gateway_http",
    "gateway_network",
    "ipsec_logs",
    "magic_ids_detections",
    "mcp_portal_logs",
    "mnm_flow_logs",
    "network_analytics_logs",
    "sinkhole_http_logs",
    "ssh_logs",
    "turnstile_events",
    "warp_config_changes",
    "warp_toggle_changes",
    "websocket_analytics",
    "workers_trace_events",
    "zero_trust_network_sessions",
  ]
}

# Platform defaults (defaults.auto.tfvars)
variable "logpush_min_zone_tier" {
  type        = string
  default     = "enterprise"
  description = <<-EOT
    Lowest zone rate plan a zone-scoped job may target. Zone Logpush is an
    Enterprise entitlement, and Cloudflare refuses the job on anything lower -
    at apply, after the plan has been approved. Lower it only if your contract
    genuinely entitles a lower plan.
  EOT

  validation {
    condition = contains([
      "free", "lite", "pro", "pro_plus", "business", "enterprise",
      "partners_free", "partners_pro", "partners_business",
      "partners_enterprise", "partners_ent",
    ], var.logpush_min_zone_tier)
    error_message = "logpush_min_zone_tier must be one of: free, lite, pro, pro_plus, business, enterprise, partners_free, partners_pro, partners_business, partners_enterprise, partners_ent."
  }
}

variable "default_logpush_job_enabled" {
  type        = bool
  default     = true
  description = "Whether a job that does not say pushes. True, against the provider's own default of false: a job declared in an account tree and created disabled looks configured and ships nothing."
}

variable "default_logpush_output_type" {
  type        = string
  default     = "ndjson"
  description = "Record format for a job that names none: \"ndjson\" or \"csv\"."

  validation {
    condition     = contains(["ndjson", "csv"], var.default_logpush_output_type)
    error_message = "default_logpush_output_type must be \"ndjson\" or \"csv\"."
  }
}

variable "default_logpush_timestamp_format" {
  type        = string
  default     = "rfc3339"
  description = <<-EOT
    Timestamp format for a job that names none. rfc3339 rather than the API's
    own default of unixnano: every SIEM parses it without a custom rule, and it
    is what a job built in the dashboard uses, so a hand-built job and a
    Terraform-built one land in the same index looking the same.
  EOT

  validation {
    condition     = contains(["unixnano", "unix", "rfc3339", "rfc3339ms", "rfc3339ns"], var.default_logpush_timestamp_format)
    error_message = "default_logpush_timestamp_format must be one of \"unixnano\", \"unix\", \"rfc3339\", \"rfc3339ms\" or \"rfc3339ns\"."
  }
}

variable "default_cve_2021_44228_redaction" {
  type        = bool
  default     = true
  description = <<-EOT
    Whether a job that does not say rewrites every "$${" in its output to "x{".
    Request logs carry whatever a client sent, Log4Shell (CVE-2021-44228)
    lookup strings included, and a log pipeline built on a vulnerable Log4j
    would evaluate them on ingest. The rewrite costs nothing a human reading the
    log needs.
  EOT
}

variable "required_logpush_account_datasets" {
  type        = list(string)
  default     = []
  description = <<-EOT
    Account-scoped datasets every account must push, e.g. ["audit_logs"]. The
    plan fails for an account with no enabled job for each one.

    Empty by default because Logpush is Enterprise-only and this layer runs for
    every account. Set it in defaults.auto.tfvars for a fleet whose accounts are
    all Enterprise and whose compliance regime needs an unbroken audit trail.
  EOT
}

# Guardrails
variable "allow_logpush_sampling" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether a job may set output_options.sample_rate below 1.

    A sampled log is missing events at random: the request that matters in an
    incident is as likely to be dropped as any other, and nothing in the log
    says so. Sampling suits a traffic-analytics feed, not a SIEM or an audit
    archive. Left false, the plan fails naming each job that samples.
  EOT
}

variable "allow_insecure_logpush_destinations" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether a destination may be plain http://, or switch certificate
    verification off with insecure-skip-verify=true.

    Logs carry client IPs, user identities, URLs and, where the fields are
    selected, cookies and headers. Over plain HTTP they cross the internet
    readable; with verification off, anything able to answer on the
    destination's address receives them. Left false, the plan fails naming the
    job. Checked against committed and secret destinations alike, and only the
    job key is ever reported.
  EOT
}
