# =============================================================================
# Layer zones - inputs.
#
# This layer owns zone identity: the zone itself, its baseline settings, and its
# DNS records. It runs first, and nothing else may destroy a zone.
#
# Two config files feed it:
#   accounts/<account>/zones.tfvars - the zone inventory, shared with every layer
#   accounts/<account>/dns.tfvars   - zone configuration, consumed only here
#
# The inventory is deliberately separate and minimal. Later layers need to know
# that key "primary" means "example.com" so they can resolve it to a zone ID, but
# they have no business seeing DNS records. Keeping identity in its own file means
# the same file can be passed to every layer without each one having to declare
# the full zone schema.
# =============================================================================

variable "cloudflare_account_id" {
  type        = string
  description = <<-EOT
    Cloudflare Account ID this layer run targets. Supplied from
    accounts/<account>/account.tfvars, or overridden with
    TF_VAR_cloudflare_account_id.
  EOT

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "zones" {
  description = <<-EOT
    Zone inventory: the logical key => domain name mapping for this account.
    Shared verbatim with layers waf and load_balancing, which resolve the
    key to a zone ID.

    The key is permanent identity. Renaming it destroys and recreates the zone,
    which takes every DNS record with it.

    - `domain_name` - The apex domain (e.g. example.com).
  EOT
  type = map(object({
    domain_name = string
  }))

  validation {
    condition     = alltrue([for key in keys(var.zones) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "zones keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
  }

  validation {
    condition     = length(distinct([for z in var.zones : lower(z.domain_name)])) == length(var.zones)
    error_message = "Each zones entry must have a distinct domain_name; Cloudflare allows one zone per domain per account."
  }
}

variable "zone_config" {
  description = <<-EOT
    Per-zone configuration, keyed by the same key as `var.zones`. A zone with no
    entry here gets the platform defaults and no DNS records.

    - `zone_type`       - (Optional) full, partial, secondary or internal. Defaults to full.
    - `paused`          - (Optional) Pause Cloudflare proxying for the whole zone.
    - `ssl_mode`        - (Optional) Edge TLS mode. Defaults to var.default_ssl_mode.
    - `min_tls_version` - (Optional) Defaults to var.default_min_tls_version.
    - `zone_settings`   - (Optional) Extra string-valued setting_id => value pairs, merged
                          over var.default_zone_settings and the module's secure baseline.
    - `dns_records`     - (Optional) Records for the zone. Names may be "@", relative or
                          fully-qualified; the module qualifies them against the zone's
                          domain. See ../../../modules/zone_base/README.md.
  EOT
  type = map(object({
    zone_type       = optional(string)
    paused          = optional(bool)
    ssl_mode        = optional(string)
    min_tls_version = optional(string)
    zone_settings   = optional(map(string), {})
    dns_records = optional(list(object({
      name     = string
      type     = string
      content  = string
      ttl      = optional(number, 1)
      proxied  = optional(bool, false)
      priority = optional(number)
      comment  = optional(string)
      tags     = optional(set(string))
    })), [])
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# Platform defaults (defaults.auto.tfvars in this directory)
# -----------------------------------------------------------------------------
variable "default_ssl_mode" {
  type        = string
  default     = "strict"
  description = "Edge TLS mode applied to any zone that does not set `ssl_mode` itself."

  validation {
    condition     = contains(["off", "flexible", "full", "strict"], var.default_ssl_mode)
    error_message = "default_ssl_mode must be one of: off, flexible, full, strict."
  }
}

variable "default_min_tls_version" {
  type        = string
  default     = "1.2"
  description = "Minimum TLS version applied to any zone that does not set `min_tls_version` itself."

  validation {
    condition     = contains(["1.0", "1.1", "1.2", "1.3"], var.default_min_tls_version)
    error_message = "default_min_tls_version must be one of: 1.0, 1.1, 1.2, 1.3."
  }
}

variable "default_zone_settings" {
  type        = map(string)
  default     = {}
  description = <<-EOT
    Zone settings applied to every zone in this account, merged under each zone's
    own `zone_settings`. The zone_base module already applies a secure baseline
    (always_use_https, tls_1_3, http3, ...), so this is for fleet-wide additions
    on top of that.
  EOT
}
