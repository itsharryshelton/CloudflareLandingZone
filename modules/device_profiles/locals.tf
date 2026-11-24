locals {
  # Cloudflare's client modes, by API name. The provider does not enumerate
  # them, so a misspelling would otherwise reach the API at apply.
  service_modes    = ["warp", "1dot1", "warp_tunnel_only", "proxy", "posture_only"]
  tunnel_protocols = ["wireguard", "masque"]

  uuid_pattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

  # A domain or a single label ("corp", "intranet"). Split tunnel hosts may also
  # carry a leading "*.".
  domain_pattern = "^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)*[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$"

  custom_profiles = {
    for key, profile in var.custom_profiles : key => merge(profile, {
      name = trimspace(profile.name)
    })
  }

  # One view of the settings both profile kinds share, labelled the way an error
  # message should name them. The default profile is folded in through a for
  # rather than a conditional, because a conditional cannot return an empty
  # object on one side and a populated one on the other.
  default_profile_by_label = { default_profile = var.default_profile }

  profile_settings = merge(
    {
      for key, p in var.custom_profiles : "custom_profiles.${key}" => {
        service_mode          = p.service_mode
        split_tunnel          = p.split_tunnel
        fallback_domains      = p.fallback_domains
        dns_search_suffixes   = p.dns_search_suffixes
        virtual_networks      = p.virtual_networks
        tunnel_protocol       = p.tunnel_protocol
        auto_connect          = p.auto_connect
        captive_portal        = p.captive_portal
        lan_allow_minutes     = p.lan_allow_minutes
        lan_allow_subnet_size = p.lan_allow_subnet_size
        support_url           = p.support_url
      }
    },
    {
      for label, p in local.default_profile_by_label : label => {
        service_mode          = p.service_mode
        split_tunnel          = p.split_tunnel
        fallback_domains      = p.fallback_domains
        dns_search_suffixes   = p.dns_search_suffixes
        virtual_networks      = p.virtual_networks
        tunnel_protocol       = p.tunnel_protocol
        auto_connect          = p.auto_connect
        captive_portal        = p.captive_portal
        lan_allow_minutes     = p.lan_allow_minutes
        lan_allow_subnet_size = p.lan_allow_subnet_size
        support_url           = p.support_url
      } if p != null
    },
  )

  # Split tunnel entries, normalised. `value` is whichever of address or host is
  # set, for duplicate detection; the check that exactly one is set is separate.
  split_entries = {
    for label, s in local.profile_settings : label => [
      for e in try(s.split_tunnel.entries, []) : {
        address     = e.address == null ? null : lower(trimspace(e.address))
        host        = e.host == null ? null : lower(trimspace(e.host))
        description = e.description
        value       = lower(trimspace(coalesce(e.address, e.host, " ")))
      }
    ]
  }

  # Provider-shaped lists. Only the list for the profile's mode is sent: the
  # other stays null, so the API is never asked to hold both.
  split_lists = {
    for label, s in local.profile_settings : label => {
      mode = try(s.split_tunnel.mode, null)
      entries = [
        for e in local.split_entries[label] : {
          address     = e.address
          host        = e.host
          description = e.description
        }
      ]
    }
  }

  fallback_lists = {
    for label, s in local.profile_settings : label => s.fallback_domains == null ? null : [
      for d in s.fallback_domains : {
        suffix      = lower(trimspace(d.suffix))
        description = d.description
        # Empty is sent as null: an empty list and an absent one mean the same
        # to Cloudflare, and only one of them round-trips without a diff.
        dns_server = length(d.dns_servers) == 0 ? null : [for ip in d.dns_servers : trimspace(ip)]
      }
    ]
  }

  # ---------------------------------------------------------------------------
  # Per-profile problems, consumed by the preconditions in main.tf. Each is a
  # list of human-readable faults, empty when the profile is sound.
  # ---------------------------------------------------------------------------

  settings_problems = {
    for label, s in local.profile_settings : label => compact(flatten([
      # Service mode
      s.service_mode == null ? [] : [
        contains(local.service_modes, try(s.service_mode.mode, "")) ? "" : "service_mode.mode \"${try(s.service_mode.mode, "")}\" is not one of ${join(", ", local.service_modes)}",
        try(s.service_mode.mode, "") == "proxy" && try(s.service_mode.port, null) == null ? "service_mode.mode \"proxy\" needs a port for the local proxy to listen on" : "",
        try(s.service_mode.mode, "") != "proxy" && try(s.service_mode.port, null) != null ? "service_mode.port is only read in proxy mode, and would be ignored in \"${try(s.service_mode.mode, "")}\"" : "",
        try(s.service_mode.port, null) == null ? "" : (try(s.service_mode.port >= 1 && s.service_mode.port <= 65535, false) ? "" : "service_mode.port must be between 1 and 65535"),
      ],

      # Split tunnel
      s.split_tunnel == null ? [] : concat(
        [
          contains(["exclude", "include"], try(s.split_tunnel.mode, "")) ? "" : "split_tunnel.mode must be \"exclude\" or \"include\", got \"${try(s.split_tunnel.mode, "")}\"",
          try(s.split_tunnel.mode, "") == "include" && length(local.split_entries[label]) == 0 ? "split_tunnel is in include mode with no entries, which sends nothing through the client - Gateway would see no traffic from these devices at all" : "",
          length(distinct([for e in local.split_entries[label] : e.value])) == length(local.split_entries[label]) ? "" : "split_tunnel.entries lists the same address or host twice",
        ],
        [
          for i, e in local.split_entries[label] : (e.address == null) == (e.host == null) ? "split_tunnel.entries[${i}] must set exactly one of address or host" : ""
        ],
        [
          for i, e in local.split_entries[label] : (
            e.address == null ? "" :
            !(strcontains(e.address, "/") && can(cidrhost(e.address, 0))) ? "split_tunnel.entries[${i}].address \"${e.address}\" is not a CIDR range - a single address needs an explicit /32 or /128" :
            cidrsubnet(e.address, 0, 0) != e.address ? "split_tunnel.entries[${i}].address \"${e.address}\" is not written as its network address; use \"${cidrsubnet(e.address, 0, 0)}\"" : ""
          )
        ],
        [
          for i, e in local.split_entries[label] : (
            e.host == null ? "" :
            can(regex(local.domain_pattern, trimprefix(e.host, "*."))) ? "" : "split_tunnel.entries[${i}].host \"${e.host}\" is not a domain name"
          )
        ],
      ),

      # Local Domain Fallback
      s.fallback_domains == null ? [] : concat(
        [
          length(distinct([for d in local.fallback_lists[label] : d.suffix])) == length(local.fallback_lists[label]) ? "" : "fallback_domains lists the same suffix twice",
        ],
        [
          for i, d in local.fallback_lists[label] : can(regex(local.domain_pattern, d.suffix)) ? "" : "fallback_domains[${i}].suffix \"${d.suffix}\" is not a domain suffix - no leading dot, no scheme"
        ],
        flatten([
          for i, d in local.fallback_lists[label] : [
            for ip in coalesce(d.dns_server, []) : (
              !strcontains(ip, "/") && (can(cidrhost("${ip}/32", 0)) || can(cidrhost("${ip}/128", 0)))
            ) ? "" : "fallback_domains[${i}].dns_servers entry \"${ip}\" is not an IP address"
          ]
        ]),
      ),

      # DNS search suffixes
      s.dns_search_suffixes == null ? [] : [
        for i, d in s.dns_search_suffixes : can(regex(local.domain_pattern, lower(trimspace(d.suffix)))) ? "" : "dns_search_suffixes[${i}].suffix \"${d.suffix}\" is not a domain suffix"
      ],

      # Virtual networks
      s.virtual_networks == null ? [] : concat(
        [
          length(try(s.virtual_networks.allowed, [])) > 0 ? "" : "virtual_networks.allowed must list at least one virtual network ID",
          contains(try(s.virtual_networks.allowed, []), try(s.virtual_networks.default, "")) ? "" : "virtual_networks.default must be one of virtual_networks.allowed",
        ],
        [
          for id in concat(try(s.virtual_networks.allowed, []), [try(s.virtual_networks.default, "")]) :
          can(regex(local.uuid_pattern, id)) ? "" : "virtual_networks entry \"${id}\" is not a virtual network ID (UUID)"
        ],
      ),

      # Scalars
      s.tunnel_protocol == null || contains(local.tunnel_protocols, coalesce(s.tunnel_protocol, "x")) ? "" : "tunnel_protocol must be \"wireguard\" or \"masque\"",
      s.auto_connect == null || try(s.auto_connect >= 0, false) ? "" : "auto_connect must be zero or a positive number of seconds",
      s.captive_portal == null || try(s.captive_portal >= 0, false) ? "" : "captive_portal must be zero or a positive number of seconds",
      s.lan_allow_minutes == null || try(s.lan_allow_minutes >= 0, false) ? "" : "lan_allow_minutes must be zero or a positive number of minutes",
      s.lan_allow_subnet_size == null || try(s.lan_allow_subnet_size >= 1 && s.lan_allow_subnet_size <= 128, false) ? "" : "lan_allow_subnet_size must be a prefix length between 1 and 128",
      s.support_url == null || can(regex("^(https://|mailto:)", coalesce(s.support_url, "x"))) ? "" : "support_url must start with https:// or mailto:",
    ]))
  }

  # ---------------------------------------------------------------------------
  # Match expressions (custom profiles only)
  # ---------------------------------------------------------------------------

  identity_terms = {
    for key, p in var.custom_profiles : key => compact([
      length(p.match.user_emails) == 0 ? "" : "identity.email in {${join(" ", [for v in p.match.user_emails : "\"${lower(trimspace(v))}\""])}}",
      length(p.match.user_group_names) == 0 ? "" : "any(identity.groups.name[*] in {${join(" ", [for v in p.match.user_group_names : "\"${trimspace(v)}\""])}})",
      length(p.match.user_group_ids) == 0 ? "" : "any(identity.groups.id[*] in {${join(" ", [for v in p.match.user_group_ids : "\"${trimspace(v)}\""])}})",
      length(p.match.user_group_emails) == 0 ? "" : "any(identity.groups.email[*] in {${join(" ", [for v in p.match.user_group_emails : "\"${lower(trimspace(v))}\""])}})",
    ])
  }

  os_terms = {
    for key, p in var.custom_profiles : key => length(p.match.os_names) == 0 ? "" : "os.name in {${join(" ", [for v in distinct(p.match.os_names) : "\"${lower(trimspace(v))}\""])}}"
  }

  compiled_matches = {
    for key, p in var.custom_profiles : key => join(" and ", compact([
      length(local.identity_terms[key]) == 0 ? "" : (
        length(local.identity_terms[key]) == 1 ? local.identity_terms[key][0] : "(${join(" or ", local.identity_terms[key])})"
      ),
      local.os_terms[key],
    ]))
  }

  matches = {
    for key, p in var.custom_profiles : key => p.match_expression != null ? trimspace(p.match_expression) : local.compiled_matches[key]
  }

  match_problems = {
    for key, p in var.custom_profiles : key => compact([
      p.match_expression == null && local.compiled_matches[key] == "" ? "names no match selector and would apply to every device. Every device without a custom profile already gets the default profile; a catch-all custom profile makes the default unreachable. Give it a match, or configure default_profile instead" : "",
      p.match_expression != null && local.compiled_matches[key] != "" ? "sets both match and match_expression. The raw expression replaces the compiled one rather than being merged with it, so one would be silently discarded" : "",
    ])
  }

  # Cross-profile assertions.

  duplicate_names = sort([
    for name, claimants in {
      for key, p in local.custom_profiles : lower(p.name) => key...
    } : "\"${name}\" (${join(", ", sort(claimants))})" if length(claimants) > 1
  ])

  duplicate_precedences = sort([
    for precedence, claimants in {
      for key, p in var.custom_profiles : tostring(p.precedence) => key...
    } : "${precedence} (${join(", ", sort(claimants))})" if length(claimants) > 1
  ])
}
