# Layer dns - DNS records for zones the zones layer owns.
#
# The zone inventory and the account ID are declared with the same shape and the
# same text as in layers/zones, because accounts/<account>/zones.tfvars and
# account.tfvars are passed to both and Terraform rejects a var file containing a
# variable the root module does not declare. See .github/scripts/tf-varfiles.sh.

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
    Zone inventory: the logical key => domain name mapping for this account,
    from accounts/<account>/zones.tfvars. Shared verbatim with every layer that
    resolves a zone key to a zone ID.

    This layer reads `domain_name` and nothing else - it is what
    data.cloudflare_zone filters on to turn a dns_config key into a zone ID.

    The key is permanent identity. It has to match the key used in dns.tfvars,
    and renaming it in the zones layer destroys and recreates the zone, which
    takes every DNS record with it.

    - `domain_name` - The apex domain (e.g. example.com).
    - `zone_tier`   - (Optional) Declared only so this file remains passable to
                      this layer; a var file carrying an attribute the root
                      module does not accept is rejected outright. The rate plan
                      is the zones layer's business, and nothing here reads it.
  EOT
  type = map(object({
    domain_name = string
    zone_tier   = optional(string)
  }))

  validation {
    condition     = alltrue([for key in keys(var.zones) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "zones keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
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

  validation {
    condition     = length(distinct([for z in var.zones : lower(z.domain_name)])) == length(var.zones)
    error_message = "Each zones entry must have a distinct domain_name; Cloudflare allows one zone per domain per account."
  }
}

# -----------------------------------------------------------------------------
# DNS records
# -----------------------------------------------------------------------------
variable "dns_config" {
  description = <<-EOT
    Per-zone DNS records, keyed by the same zone key as var.zones.

    Split out of the zones layer's `zone_config` rather than sharing it: no two
    files in an account tree may assign the same variable, because that is what
    makes the layer-to-var-file mapping derivable (see tf-varfiles.sh). So the
    zones layer keeps `zone_config` for zone settings and TLS posture, and this
    layer owns `dns_config` for records.

    A zone key with no entry here simply has no Terraform-managed records. A key
    that is not in var.zones fails the plan - see preflight.tf - because the
    alternative is a records block that silently applies to nothing.
  EOT
  type = map(object({
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
