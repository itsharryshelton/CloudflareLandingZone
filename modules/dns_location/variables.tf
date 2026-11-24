variable "account_id" {
  type        = string
  description = "Cloudflare Account ID that owns the Gateway DNS location."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "name" {
  type        = string
  description = "Display name of the DNS location, shown in the Zero Trust dashboard and against every query in the Gateway DNS logs. A DNS policy matches a location by UUID, so renaming is an in-place update."

  validation {
    condition     = trimspace(var.name) != "" && trimspace(var.name) == var.name
    error_message = "name must be non-empty and carry no leading or trailing whitespace."
  }
}

variable "client_default" {
  type        = bool
  default     = false
  description = <<-EOT
    Make this the account's default DNS location: the one the Cloudflare One
    (WARP) client's DNS queries are attributed to. An account has exactly one,
    so setting this true on one location takes the flag away from whichever held
    it - a caller managing several locations must set it on at most one.
  EOT
}

variable "ecs_support" {
  type        = bool
  default     = false
  description = "Forward EDNS Client Subnet to upstream authoritative servers. Improves geo-steered answers for the location and tells every authoritative server you query which network the query came from - off unless a CDN-heavy workload needs it."
}

variable "networks" {
  type        = list(string)
  default     = []
  description = <<-EOT
    The public IPv4 ranges this site's queries arrive from - the office's
    egress addresses as Cloudflare sees them, not its internal ranges. With the
    shared Gateway IPv4 resolver addresses, a query is attributed to this
    location only by its source address, so this is what makes the IPv4
    endpoint mean this site.

    CIDR form, /24 or smaller: Cloudflare limits a source network to a /24.
    A single address is a /32.
  EOT

  validation {
    condition     = alltrue([for cidr in var.networks : can(cidrnetmask(cidr)) && tonumber(split("/", cidr)[1]) >= 24])
    error_message = "Each networks entry must be an IPv4 CIDR of /24 or smaller (/24 to /32), such as 203.0.113.0/24. A single address needs an explicit /32."
  }

  validation {
    condition     = alltrue([for cidr in var.networks : !can(cidrnetmask(cidr)) || cidrsubnet(cidr, 0, 0) == cidr])
    error_message = "Each networks entry must sit on its network boundary - 203.0.113.0/24, not 203.0.113.7/24. Cloudflare stores the boundary, so anything else would show as drift on every plan."
  }
}

variable "dns_destination_ips_id" {
  type        = string
  default     = null
  description = "UUID of a dedicated pair of Gateway IPv4 resolver addresses (an Enterprise feature). Null uses the shared pair Cloudflare assigns every location. With a dedicated pair, queries are attributed by the destination address, so `networks` is no longer needed for the IPv4 endpoint."

  validation {
    condition     = var.dns_destination_ips_id == null || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", coalesce(var.dns_destination_ips_id, "x")))
    error_message = "dns_destination_ips_id must be a UUID when set."
  }
}

variable "endpoints" {
  type = object({
    ipv4 = optional(object({
      enabled = optional(bool, false)
    }), {})
    ipv6 = optional(object({
      enabled  = optional(bool, false)
      networks = optional(list(string), [])
    }), {})
    doh = optional(object({
      enabled       = optional(bool, false)
      networks      = optional(list(string), [])
      require_token = optional(bool, false)
    }), {})
    dot = optional(object({
      enabled  = optional(bool, false)
      networks = optional(list(string), [])
    }), {})
  })
  default     = {}
  description = <<-EOT
    Which resolver endpoints this location answers on. Every one is off unless
    switched on, so turning one on is a decision rather than a default.

      - `ipv4` - the IPv4 resolver addresses. Attributed by source address, so
                 it needs `networks` (or a dedicated dns_destination_ips_id).
      - `ipv6` - a unique IPv6 resolver address for this location.
                 `networks` restricts which source ranges it answers.
      - `doh`  - DNS over HTTPS at https://<doh_subdomain>.cloudflare-gateway.com/dns-query.
                 `networks` restricts sources; `require_token` demands a
                 user identity token, which is how a DoH endpoint can be used
                 from anywhere without being open to anyone.
      - `dot`  - DNS over TLS at <doh_subdomain>.cloudflare-gateway.com.
                 `networks` restricts sources.

    The IPv6, DoH and DoT endpoints are unique to this location, and with no
    `networks` restriction (and, for DoH, no token) they answer anybody who
    learns the address. Whoever does gets this account's DNS policies - including
    any override or resolver rule that maps internal names - and their queries
    are logged and billed as this location's. That shape is refused unless
    allow_unrestricted_endpoints is true.

    endpoint `networks` entries take IPv4 or IPv6 CIDRs (IPv6 only for `ipv6`).
  EOT

  validation {
    condition = alltrue([
      for cidr in concat(var.endpoints.doh.networks, var.endpoints.dot.networks) : can(cidrhost(cidr, 0))
    ])
    error_message = "Each endpoints.doh.networks and endpoints.dot.networks entry must be an IPv4 or IPv6 CIDR, such as 203.0.113.0/24 or 2001:db8::/48."
  }

  validation {
    condition     = alltrue([for cidr in var.endpoints.ipv6.networks : can(cidrhost(cidr, 0)) && strcontains(cidr, ":")])
    error_message = "Each endpoints.ipv6.networks entry must be an IPv6 CIDR, such as 2001:db8::/48."
  }
}

variable "max_ttl" {
  type = object({
    mode     = string
    ttl_secs = optional(number)
  })
  default     = null
  description = <<-EOT
    Cap on the TTL Gateway returns for answers to this location.

      - `inherit`  - use the account's gateway_settings.max_ttl_secs
      - `override` - use `ttl_secs` for this location
      - `disabled` - return TTLs unchanged

    Null leaves it to Cloudflare, which resets an unset value to "inherit" on
    every update.
  EOT

  validation {
    condition     = var.max_ttl == null || contains(["inherit", "override", "disabled"], try(var.max_ttl.mode, ""))
    error_message = "max_ttl.mode must be \"inherit\", \"override\" or \"disabled\"."
  }

  validation {
    condition     = var.max_ttl == null || ((try(var.max_ttl.mode, "") == "override") == (try(var.max_ttl.ttl_secs, null) != null))
    error_message = "max_ttl.ttl_secs is required when mode is \"override\" and must be omitted otherwise - Cloudflare rejects either mismatch."
  }

  validation {
    condition     = try(var.max_ttl.ttl_secs, null) == null || try(var.max_ttl.ttl_secs >= 1, false)
    error_message = "max_ttl.ttl_secs must be a positive number of seconds."
  }
}

variable "allow_unrestricted_endpoints" {
  type        = bool
  default     = false
  description = <<-EOT
    Permit an IPv6, DoH or DoT endpoint with no source restriction (and, for
    DoH, no identity token) - one that answers anybody who learns its address.

    Off because the address is not a secret in any useful sense: it is in every
    device and router configured to use it, in packet captures and in support
    tickets. Somebody who has it can resolve through this account's policies,
    read back internal names from any override or resolver rule, and have their
    queries logged as this site's. Turn it on for a location that genuinely
    serves roaming devices with no fixed source range, and prefer
    endpoints.doh.require_token = true where the clients support it.
  EOT
}
