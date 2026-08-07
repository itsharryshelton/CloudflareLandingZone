# Layer r2 - inputs.
#
# Cloudflare R2 object storage: the buckets, their CORS and lifecycle policy,
# their retention rules, and the hostnames they are served from. Holds its own
# state, so an apply here can never propose destroying a zone.
#
# Config files:
#   accounts/<account>/account.tfvars - the account ID, shared with every layer
#   accounts/<account>/zones.tfvars   - the zone inventory, shared with every layer
#   accounts/<account>/r2.tfvars      - the buckets, consumed only here

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare Account ID this layer run targets. R2 buckets are account-scoped, and the ID also forms the S3 endpoint hostname the bucket is reached on."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "zones" {
  description = <<-EOT
    Zone inventory: logical key => domain name. The same file the zones layer is
    given, so the keys mean the same thing in both.

    This layer does not create zones. It looks up only the zones a bucket's
    custom domain actually references, to get their IDs (see zone_lookup.tf),
    which keeps the two layers' states independent. A deployment with no custom
    domains costs no API call here.

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

variable "r2_buckets" {
  description = <<-EOT
    R2 buckets, keyed by a logical key.

    The key is the Terraform address and the `name` is the bucket's identity in
    Cloudflare. Renaming either destroys and recreates the bucket, and R2 has no
    versioning and no recycle bin, so that takes every object with it.

    - `name`            - Bucket name. Unique within the account and jurisdiction.
    - `location`        - (Optional) Placement hint: apac, eeur, enam, weur, wnam
                          or oc. Honoured only when the bucket is first created.
                          Falls back to `var.default_bucket_location`.
    - `storage_class`   - (Optional) Class for newly uploaded objects: Standard or
                          InfrequentAccess. Falls back to
                          `var.default_storage_class`.
    - `jurisdiction`    - (Optional) Data residency guarantee: default, eu,
                          fedramp or us. Fixed at creation - a bucket cannot be
                          moved between jurisdictions. Falls back to
                          `var.default_jurisdiction`.
    - `cors_rules`      - (Optional) Cross-origin rules. Defaults to none, which
                          is right for a bucket only ever read server-side.
    - `lifecycle_rules` - (Optional) Object expiry and storage class transitions.
                          Leave the field out entirely and the bucket inherits
                          `var.default_lifecycle_rules`; set it to `[]` to say
                          "this bucket deliberately has none".
    - `lock_rules`      - (Optional) Retention. A locked object cannot be deleted
                          by anybody, including this pipeline, until retention
                          expires.
    - `public_r2_dev_domain` - (Optional) Serve the bucket anonymously on its
                          pub-<hash>.r2.dev URL. Gated by
                          `var.allow_public_r2_dev_domains`.
    - `custom_domains`  - (Optional) Hostnames in a zone you own that serve the
                          bucket's objects. `zone_key` is taken from `var.zones`,
                          and the hostname must sit inside that zone's domain.

    Anything served publicly is served in full: R2 has no per-object ACL, so a
    public bucket is readable by anyone who knows or guesses a key. Put a Worker
    or Cloudflare Access in front of anything that is not genuinely public.
  EOT
  type = map(object({
    name          = string
    location      = optional(string)
    storage_class = optional(string)
    jurisdiction  = optional(string)

    cors_rules = optional(list(object({
      id              = optional(string)
      allowed_origins = list(string)
      allowed_methods = list(string)
      allowed_headers = optional(list(string))
      expose_headers  = optional(list(string))
      max_age_seconds = optional(number)
    })), [])

    # No default on purpose: null means "inherit the platform baseline" and []
    # means "none", and those are different answers. See locals.tf.
    lifecycle_rules = optional(list(object({
      id      = string
      enabled = optional(bool, true)
      prefix  = optional(string, "")

      abort_multipart_uploads_after_days = optional(number)

      delete_objects_after_days = optional(number)
      delete_objects_on_date    = optional(string)

      transition_to_infrequent_access_after_days = optional(number)
      transition_to_infrequent_access_on_date    = optional(string)
    })))

    lock_rules = optional(list(object({
      id                  = string
      enabled             = optional(bool, true)
      prefix              = optional(string, "")
      retain_for_days     = optional(number)
      retain_until_date   = optional(string)
      retain_indefinitely = optional(bool, false)
    })), [])

    public_r2_dev_domain = optional(bool, false)

    custom_domains = optional(list(object({
      zone_key = string
      hostname = string
      enabled  = optional(bool, true)
      min_tls  = optional(string)
      ciphers  = optional(list(string))
    })), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.r2_buckets) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "r2_buckets keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
  }

  validation {
    condition     = length(distinct([for bucket in var.r2_buckets : lower(bucket.name)])) == length(var.r2_buckets)
    error_message = "Two r2_buckets entries share a name. A bucket name is unique within an account, so the second would adopt or fight over the first's bucket."
  }

  validation {
    condition = length(distinct(flatten([
      for bucket in var.r2_buckets : [for domain in bucket.custom_domains : lower(domain.hostname)]
      ]))) == length(flatten([
      for bucket in var.r2_buckets : [for domain in bucket.custom_domains : lower(domain.hostname)]
    ]))
    error_message = "Two r2_buckets entries claim the same custom domain hostname. A hostname can only serve one bucket, so the apply order would decide which one wins."
  }
}

# Platform defaults (defaults.auto.tfvars in this directory)
variable "default_bucket_location" {
  type        = string
  default     = null
  description = <<-EOT
    Placement hint given to any bucket that names none. Null lets Cloudflare
    place each bucket automatically, near its first write.

    Set it - "weur" for a UK or European estate, say - where the fleet should
    land in one region by default rather than wherever the first upload happened
    to come from. It is a hint, not a guarantee, and it is honoured only when a
    bucket is first created; use `default_jurisdiction` for a regulatory
    requirement.
  EOT

  validation {
    condition     = var.default_bucket_location == null || contains(["apac", "eeur", "enam", "weur", "wnam", "oc"], coalesce(var.default_bucket_location, "apac"))
    error_message = "default_bucket_location must be null or one of: apac, eeur, enam, weur, wnam, oc."
  }
}

variable "default_storage_class" {
  type        = string
  default     = "Standard"
  description = <<-EOT
    Storage class newly uploaded objects land in, for any bucket that names none.

    Standard is the right default: InfrequentAccess is cheaper per byte stored,
    dearer per byte read, and carries a minimum billable storage duration, so a
    bucket whose objects turn over quickly costs more in it. Move objects across
    with a lifecycle rule once they have stopped being read.
  EOT

  validation {
    condition     = contains(["Standard", "InfrequentAccess"], var.default_storage_class)
    error_message = "default_storage_class must be Standard or InfrequentAccess."
  }
}

variable "default_jurisdiction" {
  type        = string
  default     = null
  description = <<-EOT
    Data residency jurisdiction given to any bucket that names none. Null is
    equivalent to Cloudflare's "default".

    Set it to "eu" to guarantee fleet-wide that objects never leave the EU. It is
    fixed at creation, so changing it later applies to new buckets only and an
    existing bucket has to be recreated - with its objects - to move.
  EOT

  validation {
    condition     = var.default_jurisdiction == null || contains(["default", "eu", "fedramp", "us"], coalesce(var.default_jurisdiction, "default"))
    error_message = "default_jurisdiction must be null or one of: default, eu, fedramp, us."
  }
}

variable "default_custom_domain_min_tls" {
  type        = string
  default     = "1.2"
  description = <<-EOT
    Minimum TLS version accepted by any custom domain that names none.

    Cloudflare's own default is 1.0. 1.2 is the floor every current compliance
    regime asks for, and the reason the fleet policy lives here rather than being
    retyped per bucket.
  EOT

  validation {
    condition     = contains(["1.0", "1.1", "1.2", "1.3"], var.default_custom_domain_min_tls)
    error_message = "default_custom_domain_min_tls must be one of: 1.0, 1.1, 1.2, 1.3."
  }
}

variable "default_lifecycle_rules" {
  description = <<-EOT
    Lifecycle policy applied to any bucket that declares no `lifecycle_rules` at
    all. A bucket that sets `lifecycle_rules = []` opts out and gets none.

    The shipped baseline aborts incomplete multipart uploads after seven days.
    That is the one rule worth having everywhere: a failed or abandoned upload
    leaves parts that bill like stored objects, do not appear in a bucket
    listing, and are never cleaned up otherwise. It deletes nothing an
    application successfully wrote.

    Deliberately no default expiry rule. Anything that deletes real objects is a
    per-bucket decision, on a pull request that says which data and why.
  EOT
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
  default = []
}

variable "allow_public_r2_dev_domains" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether a bucket may switch on its `pub-<hash>.r2.dev` URL.

    That URL serves every object in the bucket to anyone, with no
    authentication, no caching and no way to brand or restrict it. Cloudflare
    positions it as a development convenience, and it is one dashboard toggle
    away from any bucket.

    Left false, a bucket asking for it fails the plan naming the bucket. Serving
    objects publicly for real belongs on a `custom_domains` entry, where the
    hostname sits in a zone you own and inherits its cache, WAF and TLS posture.
  EOT
}

variable "allow_wildcard_cors_origins" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether a CORS rule may set `allowed_origins = ["*"]`.

    A wildcard origin lets any site on the internet read the bucket from a
    visitor's browser, using that visitor's network position. On a public bucket
    it is merely redundant; on a bucket reachable from inside a network it is the
    difference between "private" and "readable by any page a member of staff
    opens".

    Left false, a wildcard fails the plan naming the bucket and the rule. Listing
    the origins that actually need access is nearly always the answer.
  EOT
}

variable "allow_bucket_wide_object_expiry" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether a lifecycle rule that deletes objects may use an empty prefix.

    An empty prefix means the whole bucket, so such a rule is a scheduled,
    unrecoverable deletion of everything in it - R2 has no versioning to undo it
    with. That is occasionally exactly what is wanted, for a scratch or cache
    bucket, and is otherwise a typo in the `prefix` field.

    Left false, the plan fails naming the bucket and the rule. Aborting
    incomplete multipart uploads is not affected: it reclaims storage behind
    uploads that never completed and destroys nothing an application wrote.
  EOT
}
