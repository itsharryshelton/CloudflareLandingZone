variable "account_id" {
  type        = string
  description = "Cloudflare Account ID whose Gateway (Secure Web Gateway) DNS, network and HTTP policies this module manages."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "policies" {
  type = list(object({
    name              = string
    type              = string
    action            = string
    precedence        = number
    description       = optional(string)
    enabled           = optional(bool, true)
    match_all_traffic = optional(bool, false)

    match = optional(object({
      negate                = optional(bool, false)
      domains               = optional(list(string), [])
      hosts                 = optional(list(string), [])
      sni_domains           = optional(list(string), [])
      sni_hosts             = optional(list(string), [])
      application_ids       = optional(list(number), [])
      content_category_ids  = optional(list(number), [])
      security_category_ids = optional(list(number), [])
      destination_ip_cidrs  = optional(list(string), [])
      source_ip_cidrs       = optional(list(string), [])
      destination_ports     = optional(list(number), [])
      protocols             = optional(list(string), [])
      http_methods          = optional(list(string), [])
      dlp_profile_ids       = optional(list(string), [])
      upload_file_types     = optional(list(string), [])
      download_file_types   = optional(list(string), [])
    }), {})

    identity = optional(object({
      user_emails       = optional(list(string), [])
      user_group_names  = optional(list(string), [])
      user_group_emails = optional(list(string), [])
      user_group_ids    = optional(list(string), [])
    }), {})

    device_posture_check_ids = optional(list(string), [])

    traffic_expression        = optional(string)
    identity_expression       = optional(string)
    device_posture_expression = optional(string)

    schedule = optional(object({
      time_zone = optional(string)
      mon       = optional(string)
      tue       = optional(string)
      wed       = optional(string)
      thu       = optional(string)
      fri       = optional(string)
      sat       = optional(string)
      sun       = optional(string)
    }))

    expiration = optional(object({
      expires_at = string
      duration   = optional(number)
    }))

    settings = optional(object({
      block_reason       = optional(string)
      block_page_enabled = optional(bool)
      block_page = optional(object({
        target_uri      = string
        include_context = optional(bool)
      }))
      notification = optional(object({
        enabled         = optional(bool)
        msg             = optional(string)
        support_url     = optional(string)
        include_context = optional(bool)
      }))
      redirect = optional(object({
        target_uri              = string
        include_context         = optional(bool)
        preserve_path_and_query = optional(bool)
      }))
      check_session = optional(object({
        duration = optional(string)
        enforce  = optional(bool)
      }))
      l4_override = optional(object({
        ip   = string
        port = optional(number)
      }))
      untrusted_cert_action              = optional(string)
      payload_log_enabled                = optional(bool)
      quarantine_file_types              = optional(list(string))
      override_host                      = optional(string)
      override_ips                       = optional(list(string))
      insecure_disable_dnssec_validation = optional(bool)
      ip_categories                      = optional(bool)
      ignore_cname_category_matches      = optional(bool)
    }), {})
  }))
  default     = []
  description = <<-EOT
    Gateway policies: the corporate egress filter. Each entry becomes one
    cloudflare_zero_trust_gateway_policy, and the three policy types are three
    separate enforcement pipelines rather than one ordered list.

      - name              : display name in the Zero Trust dashboard, and this
                            policy's identity here. Matched lower-cased and trimmed.
                            Renaming destroys and recreates the policy, which is
                            harmless for a block and briefly opens a hole for an
                            allow.
      - type              : "dns", "network" or "http".
                              dns     - resolved before a connection exists. Cheapest
                                        to enforce, and blind to anything past the
                                        hostname.
                              network - the L4 connection. Ports, protocols, IPs and
                                        the TLS SNI, with no visibility into the
                                        payload.
                              http    - the decrypted L7 request. The only place a
                                        DLP profile, an upload or a URL can be seen.
      - action            : what Gateway does with a match. Valid values differ per
                            type - see the table below.
      - precedence        : evaluation order within this policy's type. Lower runs
                            first, and Gateway stops at the first allow or block it
                            matches. It is required rather than derived from list
                            order because reordering a firewall must be a visible
                            one-number diff, not a side effect of moving a block of
                            HCL.
      - description       : (Optional) shown in the dashboard and the audit log.
                            Falls back to name.
      - enabled           : (Optional) deploy the policy but leave it inactive.
                            Defaults to true.
      - match_all_traffic : (Optional) this policy deliberately names no selector and
                            therefore matches every request of its type. Required for
                            a catch-all, and refused for the actions that would turn
                            one into an open door.

    Actions, by type:

      dns     : allow, block, override, safesearch, ytrestricted
      network : allow, block, l4_override
      http    : allow, block, off, on, scan, noscan, isolate, noisolate,
                quarantine, redirect

    "off" is Do Not Inspect: the connection is passed through without TLS
    decryption. It is how a Microsoft 365 bypass is expressed, and it is also how
    an entire estate stops being inspected if it is written too broadly - so read
    the constraints on it further down.

    MATCHING

    `match` is a structured selector set compiled into a Cloudflare wirefilter
    expression, so an account tree never contains one. The compiled shape is:

      ( destination terms OR'd ) and ( each remaining constraint AND'd )

    Destination terms - alternative ways of naming the same thing, so any one of
    them matching is enough:

      domains               - the domain and every subdomain of it. dns and http only
      hosts                 - one exact hostname. dns and http only
      sni_domains           - the same, read from the TLS SNI. network only
      sni_hosts             - one exact SNI. network only
      application_ids       - Cloudflare application IDs. One application covers every
                              hostname Cloudflare knows it uses, which is what makes a
                              Microsoft 365 bypass one rule instead of forty
      content_category_ids  - Cloudflare content category IDs
      security_category_ids - Cloudflare security category IDs, e.g. malware and
                              phishing
      destination_ip_cidrs  - destination ranges. On a dns policy this is the
                              RESOLVED address, evaluated after the answer comes back

    Constraints - each is a set OR'd internally and AND'd against the rest:

      source_ip_cidrs       - where the request came from
      destination_ports     - network only
      protocols             - network only. "tcp", "udp" or "icmp"
      http_methods          - http only
      dlp_profile_ids       - http only. Data Loss Prevention profile UUIDs. A match
                              means the request body contained something the profile
                              describes
      upload_file_types     - http only. OR'd with download_file_types, because one
                              request is one direction
      download_file_types   - http only

      negate                - invert the whole compiled expression. "Everything that
                              is not this", for a default-deny rule with an allowed
                              list carved out

    `identity` restricts a policy to people rather than traffic. Its terms are
    OR'd, since they are alternative ways of naming the same population:

      user_emails, user_group_names, user_group_emails, user_group_ids

    `device_posture_check_ids` restricts to devices that PASSED the named WARP
    posture checks.

    ESCAPE HATCHES

    traffic_expression, identity_expression and device_posture_expression take a
    raw wirefilter expression and replace the compiled one for that field. Use
    them for a selector this module does not model. Nothing in the expression is
    validated here, and none of the guardrails below can see inside one.

    SETTINGS

    `settings` is the subset of Cloudflare's rule_settings that a secure web
    gateway actually configures. Each is only accepted where Cloudflare honours it:

      block_reason                       - text recorded and shown for a block
      block_page_enabled                 - serve Cloudflare's block page. dns block
      block_page                         - serve your own page instead. http block
      notification                       - the WARP client notification for a block
      redirect                           - required by action = "redirect"
      check_session                      - re-authentication interval. http and network
      l4_override                        - required by action = "l4_override"
      untrusted_cert_action              - "pass_through", "block" or "error" when the
                                           origin certificate does not validate. http
      payload_log_enabled                - STORE THE MATCHED CONTENT of a DLP hit.
                                           See the warning below. http
      quarantine_file_types              - required by action = "quarantine"
      override_host / override_ips       - required by action = "override". dns
      insecure_disable_dnssec_validation - dns
      ip_categories                      - apply category filtering to IP literals. dns
      ignore_cname_category_matches      - dns

    payload_log_enabled writes the fragment of the request that triggered the DLP
    match into Cloudflare's logs. That fragment is, by definition, the sensitive
    data the policy exists to protect - card numbers, national insurance numbers,
    source code - and it is then readable by anybody with Gateway log access. Turn
    it on for a named investigation, not as a default.

    WHAT THIS MODULE DOES NOT MANAGE

    Gateway lists, DLP profiles, proxy endpoints, account-level Gateway settings,
    browser isolation controls, header injection, egress policies and resolver
    policies. DLP profiles are referenced by ID because Cloudflare exposes no data
    source that resolves one by name.
  EOT

  validation {
    condition     = alltrue([for policy in var.policies : trimspace(policy.name) != ""])
    error_message = "Each policies[*].name must be a non-empty display name."
  }

  validation {
    condition = length(distinct([
      for policy in var.policies : lower(trimspace(policy.name))
    ])) == length(var.policies)
    error_message = "policies contains duplicate names. Names are compared lower-cased and trimmed, and they are this module's resource keys - each policy must be uniquely named."
  }

  validation {
    condition     = alltrue([for policy in var.policies : contains(["dns", "network", "http"], policy.type)])
    error_message = "Each policies[*].type must be \"dns\", \"network\" or \"http\". Egress and resolver policies are separate Gateway builders with their own actions and are not managed by this module."
  }

  # Inlined rather than held in a local: variable validation cannot reference
  # locals, and TFLint's recommended preset deletes a local nothing else reads.
  validation {
    condition = alltrue([
      for policy in var.policies : contains([
        "allow", "block", "off", "on", "scan", "noscan", "isolate", "noisolate",
        "quarantine", "redirect", "override", "safesearch", "ytrestricted",
        "l4_override",
      ], policy.action)
    ])
    error_message = "Each policies[*].action must be one of allow, block, off, on, scan, noscan, isolate, noisolate, quarantine, redirect, override, safesearch, ytrestricted, l4_override. Which of them is legal depends on the policy type, which is checked separately. \"audit_ssh\" is deprecated by Cloudflare and rejected by the provider."
  }

  validation {
    condition     = alltrue([for policy in var.policies : policy.precedence > 0])
    error_message = "Each policies[*].precedence must be greater than zero. It is the evaluation order within the policy's type, and Gateway stops at the first allow or block that matches."
  }

  # Every string below is interpolated into a Cloudflare expression inside a
  # double-quoted literal, so a value containing a quote ends the literal and the
  # rest of it becomes expression syntax.
  validation {
    condition = alltrue(flatten([
      for policy in var.policies : [
        for value in concat(
          policy.match.domains,
          policy.match.hosts,
          policy.match.sni_domains,
          policy.match.sni_hosts,
          policy.match.protocols,
          policy.match.http_methods,
          policy.match.dlp_profile_ids,
          policy.match.upload_file_types,
          policy.match.download_file_types,
          policy.identity.user_emails,
          policy.identity.user_group_names,
          policy.identity.user_group_emails,
          policy.identity.user_group_ids,
          policy.device_posture_check_ids,
        ) : trimspace(value) != "" && !strcontains(value, "\"")
      ]
    ]))
    error_message = "A policies[*] selector value is empty or contains a double quote. Every value is interpolated into a quoted Cloudflare expression literal, so a quote inside one truncates the expression and changes what the policy matches. Use traffic_expression if the expression genuinely needs to be hand-written."
  }

  validation {
    condition = alltrue(flatten([
      for policy in var.policies : [
        for cidr in concat(policy.match.destination_ip_cidrs, policy.match.source_ip_cidrs) : can(cidrnetmask(cidr))
      ]
    ]))
    error_message = "Each policies[*].match destination_ip_cidrs and source_ip_cidrs entry must be a CIDR range such as 203.0.113.0/24. A single address needs an explicit /32."
  }

  validation {
    condition = alltrue(flatten([
      for policy in var.policies : [
        for port in policy.match.destination_ports : port >= 1 && port <= 65535
      ]
    ]))
    error_message = "Each policies[*].match.destination_ports entry must be between 1 and 65535."
  }

  validation {
    condition = alltrue(flatten([
      for policy in var.policies : [
        for protocol in policy.match.protocols : contains(["tcp", "udp", "icmp"], lower(trimspace(protocol)))
      ]
    ]))
    error_message = "Each policies[*].match.protocols entry must be \"tcp\", \"udp\" or \"icmp\"."
  }

  validation {
    condition = alltrue(flatten([
      for policy in var.policies : [
        for method in policy.match.http_methods : contains(
          ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "CONNECT", "TRACE"],
          upper(trimspace(method)),
        )
      ]
    ]))
    error_message = "Each policies[*].match.http_methods entry must be a standard HTTP method: GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS, CONNECT or TRACE."
  }

  validation {
    condition = alltrue(flatten([
      for policy in var.policies : [
        for id in concat(policy.match.dlp_profile_ids, policy.device_posture_check_ids) :
        can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
      ]
    ]))
    error_message = "Each policies[*].match.dlp_profile_ids and policies[*].device_posture_check_ids entry must be a UUID. Cloudflare exposes no data source that resolves a DLP profile or a device posture check by name, so these arrive as IDs from the dashboard."
  }

  validation {
    condition = alltrue(flatten([
      for policy in var.policies : [
        for id in concat(policy.match.application_ids, policy.match.content_category_ids, policy.match.security_category_ids) : id > 0
      ]
    ]))
    error_message = "Each policies[*].match application_ids, content_category_ids and security_category_ids entry must be a positive Cloudflare identifier. Callers should resolve these from names rather than committing numbers to configuration."
  }

  # "08:00-12:30,13:30-17:00". An unparseable value is accepted by neither
  # Cloudflare nor the operator's expectation of when the rule is off.
  validation {
    condition = alltrue(flatten([
      for policy in var.policies : [
        for day in [
          try(policy.schedule.mon, null), try(policy.schedule.tue, null),
          try(policy.schedule.wed, null), try(policy.schedule.thu, null),
          try(policy.schedule.fri, null), try(policy.schedule.sat, null),
          try(policy.schedule.sun, null),
        ] : day == null || can(regex("^([0-2][0-9]:[0-5][0-9]-[0-2][0-9]:[0-5][0-9])(,[0-2][0-9]:[0-5][0-9]-[0-2][0-9]:[0-5][0-9])*$", coalesce(day, "x")))
      ]
    ]))
    error_message = "Each policies[*].schedule day must be comma-separated 24-hour intervals, for example \"08:00-12:30,13:30-17:00\". Cloudflare allows at most six intervals in a day. A day left unset means the policy does not apply that day at all."
  }

  validation {
    condition = alltrue([
      for policy in var.policies :
      policy.expiration == null || can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$", try(policy.expiration.expires_at, "")))
    ])
    error_message = "policies[*].expiration.expires_at must be an RFC 3339 timestamp with an explicit offset, for example \"2026-12-31T23:00:00Z\". A policy past its expiry stops being enforced, and Terraform will not tell you the day it happens."
  }

  validation {
    condition = alltrue([
      for policy in var.policies :
      try(policy.settings.untrusted_cert_action, null) == null || contains(["pass_through", "block", "error"], try(policy.settings.untrusted_cert_action, ""))
    ])
    error_message = "policies[*].settings.untrusted_cert_action must be \"pass_through\", \"block\" or \"error\" when set. \"pass_through\" serves the site anyway, which is the setting that quietly removes the warning a user needed to see."
  }

  validation {
    condition = alltrue([
      for policy in var.policies :
      try(policy.settings.l4_override.port, null) == null || (try(policy.settings.l4_override.port, 0) >= 1 && try(policy.settings.l4_override.port, 0) <= 65535)
    ])
    error_message = "policies[*].settings.l4_override.port must be between 1 and 65535 when set."
  }

  # Cloudflare's sandbox detonates a fixed list of formats, which is shorter than
  # the list of things somebody would want quarantined - "dll" and "scr" are both
  # rejected. The provider reports it against rule_settings.quarantine.file_types
  # with no indication of which policy, so it is caught here instead.
  validation {
    condition = alltrue(flatten([
      for policy in var.policies : [
        for file_type in coalesce(try(policy.settings.quarantine_file_types, null), []) : contains([
          "exe", "pdf", "doc", "docm", "docx", "rtf", "ppt", "pptx", "xls",
          "xlsm", "xlsx", "zip", "rar",
        ], lower(trimspace(file_type)))
      ]
    ]))
    error_message = "Each policies[*].settings.quarantine_file_types entry must be one Cloudflare's file sandbox accepts: exe, pdf, doc, docm, docx, rtf, ppt, pptx, xls, xlsm, xlsx, zip, rar. This is a shorter list than the file types a policy can MATCH on - use match.download_file_types to select the traffic, and quarantine only what the sandbox can detonate."
  }
}
