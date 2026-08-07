variable "account_id" {
  type        = string
  description = "Cloudflare Account ID that will own the zone."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "domain_name" {
  type        = string
  description = "Apex domain for the zone (e.g. example.com)."

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,}$", var.domain_name))
    error_message = "domain_name must be a valid apex domain (e.g. example.com), lowercase, no scheme or path."
  }
}

variable "zone_type" {
  type        = string
  default     = "full"
  description = "Zone setup type. One of: full, partial, secondary, internal."

  validation {
    condition     = contains(["full", "partial", "secondary", "internal"], var.zone_type)
    error_message = "zone_type must be one of: full, partial, secondary, internal."
  }
}

variable "paused" {
  type        = bool
  default     = false
  description = "Whether Cloudflare proxying is paused for the entire zone."
}

variable "ssl_mode" {
  type        = string
  default     = "strict"
  description = "Edge TLS/SSL mode. One of: off, flexible, full, strict. 'strict' is the secure default."

  validation {
    condition     = contains(["off", "flexible", "full", "strict"], var.ssl_mode)
    error_message = "ssl_mode must be one of: off, flexible, full, strict."
  }
}

variable "min_tls_version" {
  type        = string
  default     = "1.2"
  description = "Minimum TLS version accepted at the edge. One of: 1.0, 1.1, 1.2, 1.3."

  validation {
    condition     = contains(["1.0", "1.1", "1.2", "1.3"], var.min_tls_version)
    error_message = "min_tls_version must be one of: 1.0, 1.1, 1.2, 1.3."
  }
}

variable "tls_1_3" {
  type        = string
  default     = "on"
  description = <<-EOT
    TLS 1.3 support at the edge. One of: on, off, zrt.

    "zrt" is TLS 1.3 with 0-RTT resumption, which trims a round trip on repeat
    connections at the cost of making early data replayable. Only choose it if
    every endpoint reachable over early data is idempotent.

    This is independent of `min_tls_version`: setting min_tls_version = "1.3"
    forces clients up to 1.3, whereas this decides whether 1.3 is offered at all.
  EOT

  validation {
    condition     = contains(["on", "off", "zrt"], var.tls_1_3)
    error_message = "tls_1_3 must be one of: on, off, zrt (zrt enables 0-RTT resumption)."
  }
}

variable "always_use_https" {
  type        = string
  default     = "on"
  description = <<-EOT
    Redirect every plaintext HTTP request to HTTPS at the edge. One of: on, off.

    Off is almost never right on a proxied zone: it leaves the plaintext
    listener answering rather than redirecting, so a client that reaches port 80
    is served over it.
  EOT

  validation {
    condition     = contains(["on", "off"], var.always_use_https)
    error_message = "always_use_https must be one of: on, off."
  }
}

variable "zone_settings" {
  type        = map(string)
  description = <<-EOT
    Additional string-valued zone settings, applied as individual
    cloudflare_zone_setting resources (map of setting_id => value). Merged over
    the secure baseline in locals.tf; the dedicated `ssl_mode`,
    `min_tls_version`, `tls_1_3` and `always_use_https` variables always take
    precedence over any matching key here.

    The baseline is a local rather than this variable's default on purpose: a
    caller that sets zone_settings at all REPLACES a default wholesale, which is
    exactly what the deployment layers do, and the baseline used to disappear
    without a trace when they did.

    Only string-valued settings are supported by this variable; for
    numeric or object-valued settings (e.g. browser_cache_ttl), add a
    cloudflare_zone_setting resource directly. See:
    https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/zone_setting

    Note: zone settings cannot be deleted through the Cloudflare API. Removing a
    key here drops it from Terraform state but leaves the value live on the zone.
  EOT
  default     = {}

  validation {
    condition     = alltrue([for id, value in var.zone_settings : trimspace(id) != "" && trimspace(value) != ""])
    error_message = "zone_settings must not contain empty setting IDs or empty values."
  }
}

variable "dns_records" {
  type = list(object({
    name     = string
    type     = string
    content  = string
    ttl      = optional(number, 1)
    proxied  = optional(bool, false)
    priority = optional(number)
    comment  = optional(string)
    tags     = optional(set(string))
  }))
  default     = []
  description = <<-EOT
    DNS records to manage in the zone.
      - name    : "@" for the apex, a relative label ("www"), or a fully-qualified
                  name. Relative names are qualified with `domain_name` by the
                  module, because the Cloudflare API always returns FQDNs and a
                  relative name would otherwise show perpetual drift.
      - content : the record target (this replaced provider v4's `value` field).
      - ttl     : seconds; 1 means "automatic" and is required when proxied = true.
      - proxied : route the record through Cloudflare's proxy. Only valid for
                  A, AAAA and CNAME records.
      - priority: required for MX / SRV / URI record types.
    Records are keyed on type/name/content, so reordering the list never forces a
    replacement. Duplicate combinations fail the plan.
  EOT

  validation {
    condition = alltrue([
      for r in var.dns_records : contains(
        ["A", "AAAA", "CNAME", "MX", "NS", "TXT", "CAA", "SRV", "PTR", "HTTPS",
          "SVCB", "TLSA", "URI", "LOC", "CERT", "DNSKEY", "DS", "NAPTR", "SMIMEA",
        "SSHFP", "OPENPGPKEY"],
      upper(r.type))
    ])
    error_message = "Each dns_records[*].type must be a valid Cloudflare DNS record type."
  }

  validation {
    condition = alltrue([
      for r in var.dns_records :
      !contains(["MX", "SRV", "URI"], upper(r.type)) || r.priority != null
    ])
    error_message = "dns_records of type MX, SRV or URI must set `priority`."
  }

  validation {
    condition = alltrue([
      for r in var.dns_records : trimspace(r.name) != "" && trimspace(r.content) != ""
    ])
    error_message = "Each dns_records entry must set a non-empty `name` (use \"@\" for the apex) and a non-empty `content`."
  }

  validation {
    condition = alltrue([
      for r in var.dns_records : !r.proxied || r.ttl == 1
    ])
    error_message = "dns_records with proxied = true must use ttl = 1 (automatic); Cloudflare rejects an explicit TTL on a proxied record."
  }

  validation {
    condition = alltrue([
      for r in var.dns_records :
      !r.proxied || contains(["A", "AAAA", "CNAME"], upper(r.type))
    ])
    error_message = "Only A, AAAA and CNAME records can be proxied. Set proxied = false for every other record type."
  }

  validation {
    condition = alltrue([
      for r in var.dns_records : r.ttl == 1 || (r.ttl >= 30 && r.ttl <= 86400)
    ])
    error_message = "dns_records[*].ttl must be 1 (automatic) or between 30 and 86400 seconds."
  }

  validation {
    condition = alltrue([
      for r in var.dns_records : r.priority == null || (r.priority >= 0 && r.priority <= 65535)
    ])
    error_message = "dns_records[*].priority must be between 0 and 65535."
  }
}
