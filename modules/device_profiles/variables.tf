variable "account_id" {
  type        = string
  description = "Cloudflare Account ID whose Cloudflare One Client (WARP) device settings and device profiles this module manages."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

# -----------------------------------------------------------------------------
# Account-level device settings
# -----------------------------------------------------------------------------

variable "device_settings" {
  default     = null
  description = <<-EOT
    Account-wide Cloudflare One Client settings - one object per account, at
    /accounts/<id>/devices/settings. null leaves it unmanaged and whatever the
    dashboard holds stands.

    The object already exists on every Zero Trust account, but provider 5.23
    cannot adopt it with an import block ("Resource Import Not Implemented").
    The first apply therefore writes it from this configuration alone, which is
    why the four switches below are required rather than optional: an
    attribute left out would be written as unset, and turning the Gateway
    proxy off by omission removes network and HTTP filtering from every
    device. Read the current values in the dashboard (Settings > Cloudflare One
    Client > Global settings) and state each one before the first apply.

    Setting this back to null does not hand the object back to the dashboard:
    Terraform plans to delete it. Use a `removed` block with destroy = false to
    stop managing it.

    - `gateway_proxy_enabled`     - send TCP traffic from the client through the
                                    Gateway proxy. OFF, Gateway network and HTTP
                                    policies never see device traffic: only DNS
                                    policies apply, while the dashboard still
                                    lists the rest as active.
    - `gateway_udp_proxy_enabled` - the same for UDP. Needed for QUIC to be
                                    inspected rather than passed through.
    - `root_certificate_installation_enabled`
                                  - let the client install Cloudflare's managed
                                    root CA. Without a trusted root, turning on
                                    TLS decryption breaks every HTTPS site.
    - `use_zt_virtual_ip`         - give each device a CGNAT virtual IPv4
                                    (100.96.0.0/12) rather than the shared one.
                                    Needed for device-to-device and for private
                                    network policies that select a device by IP.
    - `disable_for_time`          - seconds an admin override code lets a user
                                    turn the client off. 0 or unset disables
                                    override codes.
    - `external_emergency_signal` - a URL the client polls; when it returns the
                                    disconnect signal every client disconnects.
                                    The escape hatch for a bad split tunnel or
                                    Gateway outage that has taken the fleet off
                                    the network. `url` must be https:// with an
                                    IP literal as its host, so it works when DNS
                                    through the client does not. `fingerprint`
                                    pins the server certificate (SHA-256, 64
                                    hex). `interval` is a duration of at least
                                    30s, such as "5m".
  EOT

  type = object({
    # Required rather than optional: see the description.
    gateway_proxy_enabled                 = bool
    gateway_udp_proxy_enabled             = bool
    root_certificate_installation_enabled = bool
    use_zt_virtual_ip                     = bool
    disable_for_time                      = optional(number)

    external_emergency_signal = optional(object({
      enabled     = bool
      url         = string
      fingerprint = optional(string)
      interval    = optional(string)
    }))
  })

  validation {
    condition     = try(var.device_settings.disable_for_time, null) == null || try(var.device_settings.disable_for_time >= 0, false)
    error_message = "device_settings.disable_for_time must be zero or a positive number of seconds."
  }

  validation {
    condition     = try(var.device_settings.external_emergency_signal, null) == null || can(regex("^https://(\\[[0-9a-fA-F:.]+\\]|[0-9]{1,3}(\\.[0-9]{1,3}){3})(:[0-9]{1,5})?(/.*)?$", try(var.device_settings.external_emergency_signal.url, "")))
    error_message = "device_settings.external_emergency_signal.url must be an https:// URL whose host is an IPv4 or bracketed IPv6 literal. Cloudflare refuses a hostname, because the signal has to be reachable when name resolution through the client is what has broken."
  }

  validation {
    condition     = try(var.device_settings.external_emergency_signal.fingerprint, null) == null || can(regex("^[0-9a-fA-F]{64}$", try(var.device_settings.external_emergency_signal.fingerprint, "")))
    error_message = "device_settings.external_emergency_signal.fingerprint must be the SHA-256 fingerprint of the server certificate: 64 hexadecimal characters, no colons."
  }

  validation {
    condition     = try(var.device_settings.external_emergency_signal.interval, null) == null || can(regex("^([0-9]+h)?([0-9]+m)?([0-9]+s)?$", try(var.device_settings.external_emergency_signal.interval, "x"))) && try(var.device_settings.external_emergency_signal.interval, "x") != ""
    error_message = "device_settings.external_emergency_signal.interval must be a duration such as \"30s\", \"5m\" or \"2m30s\". Cloudflare's minimum is 30 seconds."
  }
}

# -----------------------------------------------------------------------------
# Device profiles
# -----------------------------------------------------------------------------
# The settings object below is written out twice - once for the default
# profile and once inside custom_profiles - because Terraform has no type
# alias. Keep the two identical; locals.tf reads both through one projection.

variable "default_profile" {
  default     = null
  description = <<-EOT
    The account's default device profile: the settings every device gets unless
    a custom profile matches it first. One per account, it always exists, and
    the caller must import it before the first apply. null leaves it
    unmanaged.

    Takes the profile settings described under var.custom_profiles, without
    name, description, precedence, enabled or match - the default profile has
    none of those, because it is the fallback for everything.
  EOT

  type = object({
    allow_mode_switch              = optional(bool)
    allow_updates                  = optional(bool)
    allowed_to_leave               = optional(bool)
    auto_connect                   = optional(number)
    captive_portal                 = optional(number)
    disable_auto_fallback          = optional(bool)
    exclude_office_ips             = optional(bool)
    register_interface_ip_with_dns = optional(bool)
    sccm_vpn_boundary_support      = optional(bool)
    support_url                    = optional(string)
    switch_locked                  = optional(bool)
    tunnel_protocol                = optional(string)
    lan_allow_minutes              = optional(number)
    lan_allow_subnet_size          = optional(number)

    service_mode = optional(object({
      mode = string
      port = optional(number)
    }))

    split_tunnel = optional(object({
      mode = string
      entries = optional(list(object({
        address     = optional(string)
        host        = optional(string)
        description = optional(string)
      })), [])
    }))

    fallback_domains = optional(list(object({
      suffix      = string
      description = optional(string)
      dns_servers = optional(list(string), [])
    })))

    dns_search_suffixes = optional(list(object({
      suffix      = string
      description = optional(string)
    })))

    virtual_networks = optional(object({
      allowed = list(string)
      default = string
    }))
  })
}

variable "custom_profiles" {
  default     = {}
  description = <<-EOT
    Custom device profiles, keyed by a logical key. The key is the state
    address: renaming one destroys and recreates the profile under a new ID,
    and any DEX test targeting it loses its target.

    A device gets the first enabled custom profile whose match it satisfies, in
    ascending precedence, and the default profile if none does.

    IDENTITY AND ORDER
      - name              : dashboard label. Unique within this module.
      - description       : (Optional)
      - precedence        : evaluation order. Lower is evaluated first. Required
                            rather than derived from map order, so a reorder is
                            a visible one-number diff. Unique across custom
                            profiles.
      - enabled           : (Optional, default true)

    MATCH - which devices the profile applies to
      `match` is compiled into Cloudflare's wirefilter expression:

        ( identity terms OR'd ) and ( os_names )

      - user_emails       : identity.email
      - user_group_names  : identity.groups.name
      - user_group_ids    : identity.groups.id
      - user_group_emails : identity.groups.email
      - os_names          : os.name - windows, mac, linux, android, ios,
                            chromeos

      `match_expression` replaces the compiled expression, for a selector this
      module does not model (os.version, network, a SAML attribute, a service
      token). It is not validated. Exactly one of the two is required, and a
      profile that matches every device is refused: that is what the default
      profile is for, and a catch-all custom profile makes it unreachable.

    PROFILE SETTINGS (shared with var.default_profile). An attribute left
    unset does NOT keep what the dashboard holds: provider 5.23 fills most of
    them with its own default (allowed_to_leave = true, switch_locked = false,
    captive_portal = 180, ...), and the plan shows them. On an adopted default
    profile, read that first plan line by line.
      - service_mode      : { mode, port }. mode is one of
                              warp             - Traffic and DNS. Gateway sees
                                                 DNS, network and HTTP
                              1dot1            - DNS only (DoH). No network or
                                                 HTTP policy applies
                              warp_tunnel_only - Traffic only, no DNS filtering
                              proxy            - local proxy on `port`; only
                                                 what is configured to use it
                              posture_only     - device information only.
                                                 Gateway sees nothing
                            `port` is required with proxy and refused otherwise.
      - split_tunnel      : { mode, entries }. "exclude" sends everything
                            through the client except the entries; "include"
                            sends only the entries. One list per profile:
                            Cloudflare keeps one mode per profile, so an entry
                            for the other mode would never apply. Each entry
                            is exactly one of `address` (a CIDR) or `host` (a
                            domain, optionally "*."), with an optional
                            `description` shown in the client. The list
                            REPLACES Cloudflare's own: exclude mode with only
                            your entries drops Cloudflare's default RFC 1918
                            and link-local exclusions.
      - fallback_domains  : Local Domain Fallback - suffixes the client resolves
                            with the device's own resolver (or `dns_servers`)
                            rather than Gateway. null leaves the list
                            unmanaged. The list REPLACES Cloudflare's defaults
                            (local, home.arpa, corp, ...).
      - dns_search_suffixes, virtual_networks ({ allowed, default } virtual
        network IDs from the tunnels layer), switch_locked, allowed_to_leave,
        allow_mode_switch, allow_updates, auto_connect (seconds before the
        client reconnects itself; 0 never), captive_portal (seconds allowed to
        sign in to a captive portal), tunnel_protocol ("wireguard" or
        "masque"), exclude_office_ips, lan_allow_minutes,
        lan_allow_subnet_size, disable_auto_fallback,
        register_interface_ip_with_dns, sccm_vpn_boundary_support,
        support_url (https:// or mailto:).
  EOT

  type = map(object({
    name        = string
    description = optional(string)
    precedence  = number
    enabled     = optional(bool, true)

    match = optional(object({
      user_emails       = optional(list(string), [])
      user_group_names  = optional(list(string), [])
      user_group_ids    = optional(list(string), [])
      user_group_emails = optional(list(string), [])
      os_names          = optional(list(string), [])
    }), {})
    match_expression = optional(string)

    allow_mode_switch              = optional(bool)
    allow_updates                  = optional(bool)
    allowed_to_leave               = optional(bool)
    auto_connect                   = optional(number)
    captive_portal                 = optional(number)
    disable_auto_fallback          = optional(bool)
    exclude_office_ips             = optional(bool)
    register_interface_ip_with_dns = optional(bool)
    sccm_vpn_boundary_support      = optional(bool)
    support_url                    = optional(string)
    switch_locked                  = optional(bool)
    tunnel_protocol                = optional(string)
    lan_allow_minutes              = optional(number)
    lan_allow_subnet_size          = optional(number)

    service_mode = optional(object({
      mode = string
      port = optional(number)
    }))

    split_tunnel = optional(object({
      mode = string
      entries = optional(list(object({
        address     = optional(string)
        host        = optional(string)
        description = optional(string)
      })), [])
    }))

    fallback_domains = optional(list(object({
      suffix      = string
      description = optional(string)
      dns_servers = optional(list(string), [])
    })))

    dns_search_suffixes = optional(list(object({
      suffix      = string
      description = optional(string)
    })))

    virtual_networks = optional(object({
      allowed = list(string)
      default = string
    }))
  }))

  validation {
    condition     = alltrue([for key in keys(var.custom_profiles) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "custom_profiles keys must be lowercase alphanumeric with underscores. The key is a state address - renaming one recreates the profile with a new ID."
  }

  validation {
    condition     = alltrue([for p in var.custom_profiles : trimspace(p.name) != ""])
    error_message = "custom_profiles[*].name must not be empty."
  }

  validation {
    condition     = alltrue([for p in var.custom_profiles : p.precedence > 0 && floor(p.precedence) == p.precedence])
    error_message = "custom_profiles[*].precedence must be a positive whole number. Lower is evaluated first."
  }

  # Interpolated into a quoted wirefilter literal, so a quote would end the
  # literal and turn the rest of the value into expression syntax.
  validation {
    condition = alltrue(flatten([
      for p in var.custom_profiles : [
        for value in concat(p.match.user_emails, p.match.user_group_names, p.match.user_group_ids, p.match.user_group_emails) :
        trimspace(value) != "" && !strcontains(value, "\"")
      ]
    ]))
    error_message = "A custom_profiles[*].match value is empty or contains a double quote. Every value is interpolated into a quoted Cloudflare expression literal. Use match_expression if the expression genuinely needs to be hand-written."
  }

  validation {
    condition = alltrue(flatten([
      for p in var.custom_profiles : [
        for os in p.match.os_names : contains(["windows", "mac", "linux", "android", "ios", "chromeos"], lower(trimspace(os)))
      ]
    ]))
    error_message = "Each custom_profiles[*].match.os_names entry must be one of windows, mac, linux, android, ios, chromeos."
  }

  validation {
    condition     = alltrue([for p in var.custom_profiles : p.match_expression == null || trimspace(coalesce(p.match_expression, " ")) != ""])
    error_message = "custom_profiles[*].match_expression must not be empty when set. Leave it unset to use the compiled match."
  }
}
