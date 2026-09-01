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
                            HCL. Must be unique across EVERY policy in the account,
                            not just within the type: Cloudflare stores all three
                            builders in one rule collection and rejects a reused
                            number with 409.
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
    error_message = "Each policies[*].precedence must be greater than zero. It is the evaluation order within the policy's type, and Gateway stops at the first allow or block that matches. It must also be unique across every policy in the account regardless of type - see the duplicate_precedences precondition in main.tf."
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

# -----------------------------------------------------------------------------
# Account-level configuration (settings.tf)
# -----------------------------------------------------------------------------

variable "settings" {
  default     = null
  description = <<-EOT
    Account-level Gateway configuration - one object per Cloudflare account,
    stored at /accounts/<id>/gateway/configuration. null leaves it unmanaged and
    whatever the dashboard holds stands.

    This object already exists on every Zero Trust account, so the caller must
    import it before the first apply. Managing it without importing means
    Terraform writes the object from this configuration alone.

    - `tls_decrypt.enabled` - inspect HTTPS. Off, Gateway sees the TLS handshake
      and the SNI and nothing else, so every HTTP policy applies to plaintext
      HTTP only while still appearing enforced in the dashboard. This is the
      switch that makes an HTTP policy set real. Turning it on requires the
      Cloudflare root CA to be trusted by every device on WARP, or browsers get
      certificate errors on every site.
    - `inspection.mode` - "static" inspects the ports Cloudflare associates with
      HTTP/HTTPS, "dynamic" detects the protocol from the first bytes and so
      also catches HTTPS on a non-standard port. Requires tls_decrypt.
    - `protocol_detection.enabled` - identify the protocol from the initial bytes
      of a connection rather than trusting the port. What lets a network policy
      match something hiding on 443.
    - `certificate.id` - the CA Gateway presents when it decrypts. Unset means
      Cloudflare's own managed certificate. A customer-supplied CA is the option
      when the root is already distributed by MDM.
    - `body_scanning.inspection_mode` - "deep" scans the whole request body for
      DLP, "shallow" scans the first portion. Deep is the accurate one and the
      expensive one. Only meaningful with tls_decrypt on.
    - `antivirus` - scan uploads and downloads. `fail_closed` blocks anything
      that could not be scanned, including files past the size limit, so it
      turns a scanner fault into a download outage - gated behind
      allow_antivirus_fail_closed.
    - `sandbox` - detonate files before delivery. `fallback_action` is what
      happens when the sandbox cannot reach a verdict.
    - `block_page` - the page a blocked user is shown. Account-wide; a policy can
      still override the text.
    - `activity_log.enabled` - write Gateway activity logs. Off, there is no
      record of what was allowed or blocked.
    - `browser_isolation` - clientless isolation and isolation for non-identity
      onramps.
    - `extended_email_matching.enabled` - treat user+tag@ and dotted variants as
      the same identity, so an email policy cannot be sidestepped by adding a
      full stop.
    - `fips.tls` - restrict to FIPS 140-2 approved ciphers. Breaks any endpoint
      that offers nothing on that list.
    - `host_selector.enabled` - allow egress policies to select on hostname.
    - `max_ttl_secs` - cap on the TTL Gateway returns for a DNS answer.
  EOT

  type = object({
    tls_decrypt        = optional(object({ enabled = bool }))
    inspection         = optional(object({ mode = string }))
    protocol_detection = optional(object({ enabled = bool }))
    activity_log       = optional(object({ enabled = bool }))
    host_selector      = optional(object({ enabled = bool }))
    fips               = optional(object({ tls = bool }))
    max_ttl_secs       = optional(number)

    extended_email_matching = optional(object({ enabled = bool }))
    certificate             = optional(object({ id = string }))
    body_scanning           = optional(object({ inspection_mode = string }))

    antivirus = optional(object({
      enabled_download_phase = optional(bool)
      enabled_upload_phase   = optional(bool)
      fail_closed            = optional(bool)

      notification_settings = optional(object({
        enabled         = optional(bool)
        include_context = optional(bool)
        msg             = optional(string)
        support_url     = optional(string)
      }))
    }))

    sandbox = optional(object({
      enabled         = optional(bool)
      fallback_action = optional(string)
    }))

    browser_isolation = optional(object({
      non_identity_enabled          = optional(bool)
      url_browser_isolation_enabled = optional(bool)
    }))

    block_page = optional(object({
      enabled          = optional(bool)
      mode             = optional(string)
      name             = optional(string)
      header_text      = optional(string)
      footer_text      = optional(string)
      background_color = optional(string)
      logo_path        = optional(string)
      mailto_address   = optional(string)
      mailto_subject   = optional(string)
      include_context  = optional(bool)
      suppress_footer  = optional(bool)
      target_uri       = optional(string)
    }))
  })

  validation {
    condition     = contains(["static", "dynamic"], try(var.settings.inspection.mode, "static"))
    error_message = "settings.inspection.mode must be \"static\" or \"dynamic\"."
  }

  validation {
    condition     = contains(["deep", "shallow"], try(var.settings.body_scanning.inspection_mode, "deep"))
    error_message = "settings.body_scanning.inspection_mode must be \"deep\" or \"shallow\"."
  }

  validation {
    condition     = contains(["allow", "block"], try(var.settings.sandbox.fallback_action, "allow"))
    error_message = "settings.sandbox.fallback_action must be \"allow\" or \"block\"."
  }

  validation {
    condition     = contains(["", "customized_block_page", "redirect_uri"], try(var.settings.block_page.mode, ""))
    error_message = "settings.block_page.mode must be \"\", \"customized_block_page\" or \"redirect_uri\"."
  }

  validation {
    condition     = try(var.settings.certificate.id, null) == null || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", try(var.settings.certificate.id, "")))
    error_message = "settings.certificate.id must be the UUID of a certificate already available to this account."
  }

  # The certificate is what Gateway presents when it decrypts, so naming one
  # while inspection is off configures nothing and reads as though it did.
  validation {
    condition     = try(var.settings.tls_decrypt.enabled, false) || try(var.settings.certificate.id, null) == null
    error_message = "settings.certificate.id names an inspection CA while settings.tls_decrypt.enabled is false. The certificate is only used when Gateway decrypts, so it has no effect until inspection is on."
  }
}

variable "inspection_certificate" {
  default     = null
  description = <<-EOT
    Generate and activate the Cloudflare-managed root CA this account presents
    when Gateway decrypts HTTPS.

    null leaves certificates alone, which is correct where the CA is already
    active on the account or a customer root was uploaded out of band - name
    that one with settings.certificate.id instead.

    Set it and the module creates the certificate, activates it at the edge and
    points settings.certificate at the result, so the configuration write
    follows the certificate rather than racing it. Without an active CA,
    settings.tls_decrypt.enabled = true is rejected by the API with 400 code
    2211 and the whole configuration write fails with it.

    Activation is not the same as inspection. An activated CA that nothing
    decrypts with is invisible to users, so generating it in one change and
    turning tls_decrypt on in a later one is the order that leaves room to
    distribute the root to devices in between. Every device on WARP has to trust
    it before inspection goes on, or every HTTPS site returns a certificate
    error.

    - `validity_period_days` - certificate lifetime, 1 to 10,950 days, default
      1,826 (five years). Cloudflare only accepts it at creation, so changing it
      later replaces the certificate: a new root, to be distributed to every
      device again before the old one goes.
  EOT

  type = object({
    validity_period_days = optional(number, 1826)
  })

  validation {
    condition     = var.inspection_certificate == null || try(var.inspection_certificate.validity_period_days >= 1 && var.inspection_certificate.validity_period_days <= 10950, false)
    error_message = "inspection_certificate.validity_period_days must be between 1 and 10950 days."
  }
}

variable "allow_antivirus_fail_closed" {
  type        = bool
  default     = false
  description = <<-EOT
    Permit settings.antivirus.fail_closed = true, which blocks any file
    Cloudflare could not scan rather than delivering it.

    "Could not scan" is not only "found something suspicious" - it covers files
    over the scanner's size limit and scans that timed out, so an antivirus fault
    presents to users as downloads failing across the estate with no obvious
    cause. It is the right setting for some accounts, and it should be a decision
    rather than something inherited from an example.
  EOT
}

variable "allow_uninspected_http_policies" {
  type        = bool
  default     = false
  description = <<-EOT
    Permit HTTP policies to exist while settings.tls_decrypt.enabled is false.

    Off by default because that combination is the quietest failure Gateway has:
    the rules are created, the dashboard lists them as active, and they are only
    ever consulted for plaintext HTTP - so on an HTTPS estate they enforce
    nothing and nothing says so.

    Set this true only where the HTTP rules are deliberately plaintext-only, or
    during a staged rollout where inspection is turned on after the policy set is
    in place.
  EOT
}
