# Layer devices - inputs.
#
# Cloudflare One Client (WARP) configuration for one account: what the client
# does on every device, and which traffic it sends through Cloudflare.
#
# Config files:
#   accounts/<account>/account.tfvars - the account ID, shared with every layer
#   accounts/<account>/devices.tfvars - device settings and device profiles
#
# This layer takes no secret.

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare Account ID this layer run targets. Supplied from accounts/<account>/account.tfvars."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "device_settings" {
  default     = null
  description = <<-EOT
    Account-wide client settings (Settings > Cloudflare One Client > Global
    settings). null leaves them unmanaged.

    - `gateway_proxy_enabled`                 - (Required) proxy TCP through
                                                Gateway. Off, network and HTTP
                                                policies see no device traffic.
    - `gateway_udp_proxy_enabled`             - (Required) the same for UDP,
                                                QUIC included.
    - `root_certificate_installation_enabled` - (Required) let the client
                                                install Cloudflare's root CA,
                                                which TLS decryption needs.
    - `use_zt_virtual_ip`                     - (Required) per-device CGNAT
                                                virtual IPs.
    - `disable_for_time`                      - (Optional) seconds an admin
                                                override code turns the client
                                                off for. Unset or 0: no codes.
    - `external_emergency_signal`             - (Optional) { enabled, url,
                                                fingerprint, interval }. A URL
                                                every client polls for a
                                                fleet-wide disconnect signal.

    The four switches are required because provider 5.23 cannot import this
    object: the first apply writes it from this file alone, and a switch left
    out would be written as unset. Copy each from the dashboard before the
    first apply. See modules/device_profiles/variables.tf.
  EOT

  type = object({
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
}

variable "device_default_profile" {
  default     = null
  description = <<-EOT
    The default device profile: what every device gets unless a custom profile
    matches it first. It always exists; imports.tf adopts it. null leaves it
    unmanaged.

    Takes the profile settings described under var.device_custom_profiles,
    without name, description, precedence, enabled or match.
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
      mode             = string
      include_baseline = optional(bool, true)
      entries = optional(list(object({
        address     = optional(string)
        host        = optional(string)
        description = optional(string)
      })), [])
    }))

    fallback_domains = optional(object({
      include_baseline = optional(bool, true)
      domains = optional(list(object({
        suffix      = string
        description = optional(string)
        dns_servers = optional(list(string), [])
      })), [])
    }))

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

variable "device_custom_profiles" {
  default     = {}
  description = <<-EOT
    Custom device profiles, keyed by a logical key. The key is the state
    address: renaming one destroys and recreates the profile under a new ID.
    A device gets the first enabled custom profile it matches, in ascending
    precedence, and the default profile if it matches none.

      - name              : dashboard label, unique in this file.
      - description       : (Optional)
      - precedence        : (Required) lower is evaluated first. Unique.
      - enabled           : (Optional, default true)
      - match             : (Optional) { user_emails, user_group_names,
                            user_group_ids, user_group_emails, os_names },
                            compiled to ( identity terms OR'd ) and ( os_names ).
                            Group names are as the identity provider sends
                            them. os_names: windows, mac, linux, android, ios,
                            chromeos.
      - match_expression  : (Optional) raw wirefilter, replacing the compiled
                            match, e.g. for os.version or a SAML attribute.
                            Exactly one of match and match_expression. A
                            profile matching every device is refused - that is
                            the default profile's job.

    Profile settings, shared with var.device_default_profile:

      - service_mode      : { mode, port }. mode is warp (Traffic and DNS),
                            1dot1 (DNS only), warp_tunnel_only (Traffic only),
                            proxy (local proxy on `port`) or posture_only
                            (device information only). Only modes in
                            allowed_device_service_modes pass the plan.
      - split_tunnel      : { mode, include_baseline, entries }.
                              mode             - "exclude": everything goes
                                                 through the client except the
                                                 entries. "include": only the
                                                 entries do.
                              entries          - each exactly one of `address`
                                                 (CIDR, written as its network
                                                 address) or `host` (domain,
                                                 optionally "*."), plus an
                                                 optional `description` shown
                                                 in the client.
                              include_baseline - (default true) in exclude mode,
                                                 prepend
                                                 baseline_split_tunnel_excludes
                                                 (the LAN and link-local ranges
                                                 Cloudflare excludes by default),
                                                 because the list replaces
                                                 Cloudflare's own. Ignored in
                                                 include mode.
                            Unset leaves the split tunnel unmanaged.
      - fallback_domains  : { include_baseline, domains }. Suffixes resolved by
                            the device's own resolver, or by `dns_servers`,
                            instead of Gateway. include_baseline (default true)
                            prepends baseline_fallback_domains, because the list
                            replaces Cloudflare's defaults. Unset leaves the
                            list unmanaged.
      - switch_locked, allowed_to_leave, allow_mode_switch - unset falls back
                            to default_device_switch_locked,
                            default_device_allowed_to_leave and
                            default_device_allow_mode_switch.
      - auto_connect (seconds, 0 never), captive_portal (seconds),
        tunnel_protocol ("wireguard" or "masque"), exclude_office_ips,
        lan_allow_minutes, lan_allow_subnet_size, disable_auto_fallback,
        register_interface_ip_with_dns, sccm_vpn_boundary_support,
        support_url (https:// or mailto:), dns_search_suffixes,
        virtual_networks ({ allowed, default } IDs from the tunnels layer's
        outputs).

    Anything else left unset takes the provider's default, not the dashboard's
    current value. The plan shows each one.
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
      mode             = string
      include_baseline = optional(bool, true)
      entries = optional(list(object({
        address     = optional(string)
        host        = optional(string)
        description = optional(string)
      })), [])
    }))

    fallback_domains = optional(object({
      include_baseline = optional(bool, true)
      domains = optional(list(object({
        suffix      = string
        description = optional(string)
        dns_servers = optional(list(string), [])
      })), [])
    }))

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
    condition     = alltrue([for key in keys(var.device_custom_profiles) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "device_custom_profiles keys must be lowercase alphanumeric with underscores. The key is a state address - renaming one recreates the profile with a new ID."
  }
}

# -----------------------------------------------------------------------------
# Platform baseline - set in defaults.auto.tfvars
# -----------------------------------------------------------------------------

variable "default_device_switch_locked" {
  type        = bool
  description = "switch_locked for a profile that does not state it. true stops users turning the client off, which is what keeps a managed device inside Gateway; an admin override code (device_settings.disable_for_time) is the sanctioned way out."
}

variable "default_device_allowed_to_leave" {
  type        = bool
  description = "allowed_to_leave for a profile that does not state it. true lets a user log the device out of the Zero Trust organisation from the client."
}

variable "default_device_allow_mode_switch" {
  type        = bool
  description = "allow_mode_switch for a profile that does not state it. true lets a user move the client to a mode - DNS only, say - that Gateway network and HTTP policies cannot see."
}

variable "baseline_split_tunnel_excludes" {
  type = list(object({
    address     = optional(string)
    host        = optional(string)
    description = optional(string)
  }))
  description = <<-EOT
    Entries prepended to every exclude-mode split tunnel whose
    include_baseline is not false. A profile's exclude list replaces
    Cloudflare's default one, so without this a profile that adds one exclusion
    silently stops excluding local networks, and printers, NAS boxes and
    hotel-room captive portals start going through Cloudflare. An entry the
    profile also lists is not repeated. Set in defaults.auto.tfvars.
  EOT
}

variable "baseline_fallback_domains" {
  type = list(object({
    suffix      = string
    description = optional(string)
    dns_servers = optional(list(string), [])
  }))
  description = "Suffixes prepended to every managed Local Domain Fallback list whose include_baseline is not false, because a managed list replaces Cloudflare's defaults and names such as .local and home.arpa then stop resolving on the local network. A suffix the profile also lists is not repeated; the profile's entry wins. Set in defaults.auto.tfvars."
}

variable "allowed_device_service_modes" {
  type        = list(string)
  description = "Client modes a profile may use. Every mode except warp removes some traffic from Gateway: 1dot1 leaves only DNS policies, warp_tunnel_only only network and HTTP, proxy only what is pointed at the proxy, and posture_only everything. Set in defaults.auto.tfvars; widen it per platform on a pull request that says which profile needs what."

  validation {
    condition     = alltrue([for mode in var.allowed_device_service_modes : contains(["warp", "1dot1", "warp_tunnel_only", "proxy", "posture_only"], mode)])
    error_message = "allowed_device_service_modes entries must be warp, 1dot1, warp_tunnel_only, proxy or posture_only."
  }
}

variable "allow_broad_split_tunnel_excludes" {
  type        = bool
  description = "Permit an exclude-mode entry broader than a /8 of routable space (0.0.0.0/0, 0.0.0.0/1, 2000::/3, ...) or a wildcard over a whole top-level domain (*.com). Such an entry takes most of the device's traffic out of Gateway while every policy still reads as enforced. Set in defaults.auto.tfvars."
}
