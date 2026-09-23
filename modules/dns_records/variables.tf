variable "zone_id" {
  type        = string
  description = <<-EOT
    Cloudflare Zone ID the records belong to.

    Taken as an ID rather than created here, because this module exists to be
    called from a layer that does not own the zone - see the header of main.tf.
  EOT

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.zone_id))
    error_message = "zone_id must be a 32-character hexadecimal Cloudflare zone identifier."
  }
}

variable "domain_name" {
  type        = string
  description = <<-EOT
    Apex domain of the zone. Used only to qualify relative record names, which
    is why it is required even though zone_id already identifies the zone: the
    Cloudflare API returns fully-qualified names, so "www" has to become
    "www.example.com" before it is sent or every plan shows drift.
  EOT

  # Labels accept lowercase Unicode letters, not just ASCII
  validation {
    condition     = can(regex("^([0-9\\p{Ll}\\p{Lo}\\p{M}]([0-9\\p{Ll}\\p{Lo}\\p{M}-]{0,61}[0-9\\p{Ll}\\p{Lo}\\p{M}])?\\.)+[\\p{Ll}\\p{Lo}]{2,}$", var.domain_name))
    error_message = "domain_name must be a valid apex domain (e.g. example.com), lowercase, no scheme or path."
  }

  # Cloudflare normalises IDN zone names to Unicode on read, so a punycode name
  # never matches what the API returns, and every plan then shows drift on the
  # records this qualifies.
  validation {
    condition     = !can(regex("(^|\\.)xn--", var.domain_name))
    error_message = "domain_name must use the Unicode form of an IDN (e.g. café-example.fr), not punycode - Cloudflare returns the Unicode name, so a punycode value shows drift on every plan."
  }
}

variable "records" {
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
      for r in var.records : contains(
        ["A", "AAAA", "CNAME", "MX", "NS", "TXT", "CAA", "SRV", "PTR", "HTTPS",
          "SVCB", "TLSA", "URI", "LOC", "CERT", "DNSKEY", "DS", "NAPTR", "SMIMEA",
        "SSHFP", "OPENPGPKEY"],
      upper(r.type))
    ])
    error_message = "Each records[*].type must be a valid Cloudflare DNS record type."
  }

  validation {
    condition = alltrue([
      for r in var.records :
      !contains(["MX", "SRV", "URI"], upper(r.type)) || r.priority != null
    ])
    error_message = "records of type MX, SRV or URI must set `priority`."
  }

  validation {
    condition = alltrue([
      for r in var.records : trimspace(r.name) != "" && trimspace(r.content) != ""
    ])
    error_message = "Each records entry must set a non-empty `name` (use \"@\" for the apex) and a non-empty `content`."
  }

  validation {
    condition = alltrue([
      for r in var.records : !r.proxied || r.ttl == 1
    ])
    error_message = "records with proxied = true must use ttl = 1 (automatic); Cloudflare rejects an explicit TTL on a proxied record."
  }

  validation {
    condition = alltrue([
      for r in var.records :
      !r.proxied || contains(["A", "AAAA", "CNAME"], upper(r.type))
    ])
    error_message = "Only A, AAAA and CNAME records can be proxied. Set proxied = false for every other record type."
  }

  validation {
    condition = alltrue([
      for r in var.records : r.ttl == 1 || (r.ttl >= 30 && r.ttl <= 86400)
    ])
    error_message = "records[*].ttl must be 1 (automatic) or between 30 and 86400 seconds."
  }

  validation {
    condition = alltrue([
      for r in var.records : r.priority == null || (r.priority >= 0 && r.priority <= 65535)
    ])
    error_message = "records[*].priority must be between 0 and 65535."
  }
}
