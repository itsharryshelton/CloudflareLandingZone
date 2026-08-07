variable "account_id" {
  type        = string
  description = "Cloudflare Account ID. R2 buckets are account-scoped resources."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "name" {
  type        = string
  description = <<-EOT
    Bucket name. Unique within the account and jurisdiction, and part of the
    S3 endpoint path, so it is the bucket's identity - renaming one destroys and
    recreates it, taking every object with it.
  EOT

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.name))
    error_message = "name must be 3-63 characters of lowercase letters, numbers and hyphens, beginning and ending with a letter or number."
  }
}

variable "location" {
  type        = string
  default     = null
  description = <<-EOT
    Location hint for where objects are stored. One of: apac, eeur, enam, weur,
    wnam, oc. Null lets Cloudflare place the bucket automatically, near the first
    write.

    Cloudflare honours this only when the bucket is first created, and it is a
    hint rather than a guarantee. Deleting a bucket and recreating it under the
    same name keeps the original location, so a changed value on an existing
    bucket does nothing. Use `jurisdiction` where the requirement is regulatory
    rather than a latency preference.
  EOT

  validation {
    condition     = var.location == null || contains(["apac", "eeur", "enam", "weur", "wnam", "oc"], coalesce(var.location, "apac"))
    error_message = "location must be null or one of: apac, eeur, enam, weur, wnam, oc."
  }
}

variable "storage_class" {
  type        = string
  default     = "Standard"
  description = <<-EOT
    Storage class applied to newly uploaded objects that do not specify one. One
    of: Standard, InfrequentAccess.

    InfrequentAccess is cheaper to store and dearer to read, and carries a
    minimum storage duration - a bucket of objects rewritten daily costs more in
    it, not less. Prefer Standard here and move ageing objects across with a
    `lifecycle_rules` entry.
  EOT

  validation {
    condition     = contains(["Standard", "InfrequentAccess"], var.storage_class)
    error_message = "storage_class must be Standard or InfrequentAccess."
  }
}

variable "jurisdiction" {
  type        = string
  default     = null
  description = <<-EOT
    Data residency jurisdiction. One of: default, eu, fedramp, us. Null is
    equivalent to "default".

    Unlike `location` this is a guarantee rather than a hint, and it is fixed at
    creation: a bucket cannot be moved between jurisdictions, and a bucket in a
    non-default jurisdiction is reached through a different S3 endpoint. Every
    resource that configures the bucket has to name the same jurisdiction, which
    this module does for you.
  EOT

  validation {
    condition     = var.jurisdiction == null || contains(["default", "eu", "fedramp", "us"], coalesce(var.jurisdiction, "default"))
    error_message = "jurisdiction must be null or one of: default, eu, fedramp, us."
  }
}

# CORS
variable "cors_rules" {
  type = list(object({
    id              = optional(string)
    allowed_origins = list(string)
    allowed_methods = list(string)
    allowed_headers = optional(list(string))
    expose_headers  = optional(list(string))
    max_age_seconds = optional(number)
  }))
  default     = []
  description = <<-EOT
    Cross-origin rules applied when a browser reads the bucket over the S3 API,
    the r2.dev domain or a custom domain. An empty list removes CORS entirely,
    which is the correct posture for a bucket only ever read server-side.

      - id             : optional label, shown in the dashboard. Must be unique.
      - allowed_origins: origins echoed back in Access-Control-Allow-Origin.
                         "*" allows every site on the internet to read the
                         bucket from a visitor's browser - see the
                         allow_wildcard_cors_origins gate in the r2 layer.
      - allowed_methods: one or more of GET, PUT, POST, DELETE, HEAD.
      - allowed_headers: request headers a cross-origin caller may send. Needed
                         for custom headers such as x-user-id.
      - expose_headers : response headers the calling JavaScript may read,
                         beyond the CORS-safelisted set.
      - max_age_seconds: how long a browser may cache the preflight response.
                         0-86400; browsers commonly cap this at two hours.
  EOT

  validation {
    condition     = alltrue([for rule in var.cors_rules : length(rule.allowed_origins) > 0])
    error_message = "Each cors_rules[*].allowed_origins must name at least one origin."
  }

  validation {
    condition     = alltrue([for rule in var.cors_rules : length(rule.allowed_methods) > 0])
    error_message = "Each cors_rules[*].allowed_methods must name at least one method."
  }

  validation {
    condition = alltrue(flatten([
      for rule in var.cors_rules : [
        for method in rule.allowed_methods : contains(["GET", "PUT", "POST", "DELETE", "HEAD"], upper(method))
      ]
    ]))
    error_message = "Each cors_rules[*].allowed_methods entry must be one of GET, PUT, POST, DELETE, HEAD."
  }

  validation {
    condition = alltrue([
      for rule in var.cors_rules :
      rule.max_age_seconds == null || (coalesce(rule.max_age_seconds, 0) >= 0 && coalesce(rule.max_age_seconds, 0) <= 86400)
    ])
    error_message = "Each cors_rules[*].max_age_seconds, when set, must be between 0 and 86400."
  }
}

# ---------------------------------------------------------------------------
# Object lifecycle
# ---------------------------------------------------------------------------
variable "lifecycle_rules" {
  type = list(object({
    id      = string
    enabled = optional(bool, true)
    prefix  = optional(string, "")

    abort_multipart_uploads_after_days = optional(number)

    delete_objects_after_days = optional(number)
    delete_objects_on_date    = optional(string)

    transition_to_infrequent_access_after_days = optional(number)
    transition_to_infrequent_access_on_date    = optional(string)
  }))
  default     = []
  description = <<-EOT
    Object lifecycle rules. Ages are expressed in whole days here and converted
    to the seconds the R2 API wants in locals.tf, so nobody has to write 604800
    and hope.

      - id                                : unique label for the rule.
      - enabled                           : leave a rule in place but inert.
      - prefix                            : scopes the rule to object keys
                                            beginning with it. An empty prefix
                                            means the whole bucket - see the
                                            allow_bucket_wide_object_expiry gate
                                            in the r2 layer.
      - abort_multipart_uploads_after_days: reclaims the storage behind uploads
                                            that were started and never
                                            completed. Bills until aborted and is
                                            invisible in the object listing, so
                                            this is the one rule worth having
                                            everywhere.
      - delete_objects_after_days         : permanently deletes objects this many
                                            days after they were written.
      - delete_objects_on_date            : the same, but at a fixed instant.
                                            RFC3339, not a bare date - R2 rejects
                                            "2027-01-01" and wants
                                            "2027-01-01T00:00:00Z".
      - transition_to_infrequent_access_* : moves ageing objects to the cheaper,
                                            dearer-to-read class, by age or on a
                                            date.

    Deletion is not recoverable: R2 has no versioning and no recycle bin.
  EOT

  validation {
    condition     = alltrue([for rule in var.lifecycle_rules : can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$", rule.id))])
    error_message = "Each lifecycle_rules[*].id must be 1-63 characters of letters, numbers, underscores, dots or hyphens, starting with a letter or number."
  }

  validation {
    condition = alltrue([
      for rule in var.lifecycle_rules :
      rule.abort_multipart_uploads_after_days != null
      || rule.delete_objects_after_days != null
      || rule.delete_objects_on_date != null
      || rule.transition_to_infrequent_access_after_days != null
      || rule.transition_to_infrequent_access_on_date != null
    ])
    error_message = "Each lifecycle_rules entry must declare at least one transition. A rule with none is accepted by Cloudflare and does nothing, which reads in the dashboard as a policy that is in force."
  }

  validation {
    condition = alltrue([
      for rule in var.lifecycle_rules :
      !(rule.delete_objects_after_days != null && rule.delete_objects_on_date != null)
    ])
    error_message = "A lifecycle_rules entry sets both delete_objects_after_days and delete_objects_on_date. R2 accepts one deletion condition per rule - split it into two rules if you meant both."
  }

  validation {
    condition = alltrue([
      for rule in var.lifecycle_rules :
      !(rule.transition_to_infrequent_access_after_days != null && rule.transition_to_infrequent_access_on_date != null)
    ])
    error_message = "A lifecycle_rules entry sets both transition_to_infrequent_access_after_days and transition_to_infrequent_access_on_date. R2 accepts one storage class condition per rule."
  }

  validation {
    condition = alltrue([
      for rule in var.lifecycle_rules : alltrue([
        for days in [
          rule.abort_multipart_uploads_after_days,
          rule.delete_objects_after_days,
          rule.transition_to_infrequent_access_after_days,
        ] : days == null || coalesce(days, 1) >= 1
      ])
    ])
    error_message = "Every lifecycle_rules[*] day count must be at least 1. Zero would expire an object the moment it is written."
  }

  validation {
    condition = alltrue([
      for rule in var.lifecycle_rules : alltrue([
        for date in compact([rule.delete_objects_on_date, rule.transition_to_infrequent_access_on_date]) :
        can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$", date))
      ])
    ])
    error_message = "Each lifecycle_rules[*] date must be a full RFC3339 timestamp, e.g. \"2027-01-01T00:00:00Z\". R2 rejects a bare \"2027-01-01\", and it does so from the provider rather than the plan, so the message names a type rather than the rule."
  }
}

# Object lock (retention)
variable "lock_rules" {
  type = list(object({
    id                  = string
    enabled             = optional(bool, true)
    prefix              = optional(string, "")
    retain_for_days     = optional(number)
    retain_until_date   = optional(string)
    retain_indefinitely = optional(bool, false)
  }))
  default     = []
  description = <<-EOT
    Retention rules. A locked object cannot be deleted or overwritten by anybody
    - not the application, not an operator with full R2 credentials, and not a
    lifecycle rule - until its retention expires. That is the point of it, and
    also the risk: a rule is far easier to add than to live with.

      - id                 : unique label for the rule.
      - enabled            : leave a rule in place but inert.
      - prefix             : scopes the rule to object keys beginning with it.
                             Empty means the whole bucket.
      - retain_for_days    : retain each object for this long after it is written.
      - retain_until_date  : retain every matching object until a fixed instant,
                             written as RFC3339, e.g. "2030-01-01T00:00:00Z".
      - retain_indefinitely: never expires. Objects under this rule can never be
                             removed, and neither can the bucket while they are
                             in it.

    Exactly one of the three retention fields per rule.
  EOT

  validation {
    condition     = alltrue([for rule in var.lock_rules : can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$", rule.id))])
    error_message = "Each lock_rules[*].id must be 1-63 characters of letters, numbers, underscores, dots or hyphens, starting with a letter or number."
  }

  validation {
    condition = alltrue([
      for rule in var.lock_rules :
      length(compact([
        rule.retain_for_days == null ? "" : "days",
        rule.retain_until_date == null ? "" : "date",
        rule.retain_indefinitely ? "indefinite" : "",
      ])) == 1
    ])
    error_message = "Each lock_rules entry must set exactly one of retain_for_days, retain_until_date or retain_indefinitely."
  }

  validation {
    condition     = alltrue([for rule in var.lock_rules : rule.retain_for_days == null || coalesce(rule.retain_for_days, 1) >= 1])
    error_message = "Each lock_rules[*].retain_for_days, when set, must be at least 1."
  }

  validation {
    condition = alltrue([
      for rule in var.lock_rules :
      rule.retain_until_date == null || can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$", coalesce(rule.retain_until_date, "1970-01-01T00:00:00Z")))
    ])
    error_message = "Each lock_rules[*].retain_until_date must be a full RFC3339 timestamp, e.g. \"2030-01-01T00:00:00Z\". R2 rejects a bare date."
  }
}

# Public access
variable "manage_r2_dev_domain" {
  type        = bool
  default     = true
  description = <<-EOT
    Whether this module owns the bucket's r2.dev public URL setting.

    Left true, the setting is declared either way and Terraform reverts anybody
    who flips it in the dashboard, which is the whole reason to manage it: the
    r2.dev domain is the one control that turns a private bucket into an
    anonymously readable one, and it is two clicks away.

    Set it false only when adopting an account whose r2.dev state is deliberately
    managed elsewhere.
  EOT
}

variable "public_r2_dev_domain" {
  type        = bool
  default     = false
  description = <<-EOT
    Serve the bucket's contents anonymously over its `pub-<hash>.r2.dev` URL.

    Everything in the bucket becomes readable by anyone who knows or guesses an
    object key. There is no authentication, the URL cannot be branded, and
    Cloudflare deliberately rate limits and does not cache it, so it is meant for
    development rather than for serving a site.

    Use `custom_domains` for anything real: a custom domain puts the bucket
    behind a zone you own, and so behind the cache, the WAF and the rest of the
    zone's controls.
  EOT
}

variable "custom_domains" {
  type = list(object({
    domain  = string
    zone_id = string
    enabled = optional(bool, true)
    min_tls = optional(string, "1.2")
    ciphers = optional(list(string))
  }))
  default     = []
  description = <<-EOT
    Hostnames in a Cloudflare zone that serve the bucket's objects publicly.

      - domain : fully-qualified hostname, which must sit inside the zone.
      - zone_id: the zone that hostname belongs to. Cloudflare creates the DNS
                 record and issues the certificate.
      - enabled: false leaves the domain attached but stops it serving. The
                 hostname keeps returning an error rather than 404-ing into the
                 wider internet, which is the safer way to take a bucket offline.
      - min_tls: minimum TLS version accepted. One of 1.0, 1.1, 1.2, 1.3.
                 Defaults to 1.2 here rather than Cloudflare's 1.0.
      - ciphers: optional TLS cipher allowlist, in BoringSSL naming. Leave unset
                 unless a compliance regime names specific ciphers - an allowlist
                 that omits what modern clients offer takes the domain off the
                 air.

    A custom domain serves every object in the bucket to anyone who asks. R2 has
    no per-object ACL, so put a Worker or Cloudflare Access in front of anything
    that is not genuinely public.
  EOT

  validation {
    condition = alltrue([
      for domain in var.custom_domains :
      can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,}$", lower(domain.domain)))
    ])
    error_message = "Each custom_domains[*].domain must be a fully-qualified, lowercase hostname (e.g. assets.example.com) with no scheme, port or path."
  }

  validation {
    condition     = alltrue([for domain in var.custom_domains : contains(["1.0", "1.1", "1.2", "1.3"], domain.min_tls)])
    error_message = "Each custom_domains[*].min_tls must be one of: 1.0, 1.1, 1.2, 1.3."
  }

  validation {
    condition     = alltrue([for domain in var.custom_domains : domain.ciphers == null || length(coalesce(domain.ciphers, [])) > 0])
    error_message = "Each custom_domains[*].ciphers, when set, must contain at least one cipher. An empty allowlist takes the domain off the air."
  }
}
