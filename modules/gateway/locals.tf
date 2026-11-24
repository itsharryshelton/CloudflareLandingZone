# Gateway policy compilation.
#
# Every map indexed by a computed key is built with tomap() and uniform value
# types. An object literal whose attributes differ in type cannot be indexed by
# anything Terraform does not know at parse time.
#
# Whether a selector is in use is decided from list LENGTHS, never from the
# compiled string. A list or DLP profile created in the same apply has an ID
# Terraform does not know until then, so a string built from it is unknown at
# plan, and a guardrail comparing that string with "" would be deferred to apply
# - after the list it was guarding had already been created. A length is known
# even when the elements are not.

locals {
  policies    = { for policy in var.policies : lower(trimspace(policy.name)) => policy }
  policy_keys = keys(local.policies)

  # Selectors that name WHAT is being reached. OR'd together, because they are alternative ways of describing one destination.
  destination_selectors = [
    "domains", "hosts", "sni_domains", "sni_hosts", "applications",
    "content_categories", "security_categories", "destination_ips",
  ]

  # Gateway list references. Destination terms as well, one term per list,
  # because each list is its own `in $<uuid>` clause.
  destination_list_selectors = [
    "domain_lists", "host_lists", "sni_domain_lists", "sni_host_lists",
    "url_lists", "destination_ip_lists",
  ]

  # Selectors that NARROW a match. AND'd against the destination clause and against each other.
  constraint_selectors = ["source_ips", "destination_ports", "protocols", "http_methods", "dlp_profiles", "dns_locations"]

  # One request is an upload or a download, never both, so these are OR'd with each other and AND'd with everything else.
  file_selectors = ["upload_file_types", "download_file_types"]

  literal_selectors = concat(local.destination_selectors, local.constraint_selectors, local.file_selectors)
  list_selectors    = concat(local.destination_list_selectors, ["source_ip_lists"])
  all_selectors     = concat(local.literal_selectors, local.list_selectors)

  # An empty template means the selector does not exist for that policy type.
  # A DNS policy cannot see a file type; a network policy sees a TLS SNI rather than an HTTP Host header; only HTTP is past decryption, so only HTTP can match a DLP profile.
  traffic_field_templates = {
    dns = tomap({
      domains             = "any(dns.domains[*] in {%s})"
      hosts               = "dns.fqdn in {%s}"
      sni_domains         = ""
      sni_hosts           = ""
      applications        = "any(app.ids[*] in {%s})"
      content_categories  = "any(dns.content_category[*] in {%s})"
      security_categories = "any(dns.security_category[*] in {%s})"
      destination_ips     = "any(dns.resolved_ips[*] in {%s})"
      source_ips          = "dns.src_ip in {%s}"
      destination_ports   = ""
      protocols           = ""
      http_methods        = ""
      dlp_profiles        = ""
      dns_locations       = "dns.location in {%s}"
      upload_file_types   = ""
      download_file_types = ""
    })

    network = tomap({
      domains             = ""
      hosts               = ""
      sni_domains         = "any(net.sni.domains[*] in {%s})"
      sni_hosts           = "net.sni.host in {%s}"
      applications        = "any(app.ids[*] in {%s})"
      content_categories  = "any(net.fqdn.content_category[*] in {%s})"
      security_categories = "any(net.fqdn.security_category[*] in {%s})"
      destination_ips     = "any(net.dst.ip[*] in {%s})"
      source_ips          = "any(net.src.ip[*] in {%s})"
      destination_ports   = "net.dst.port in {%s}"
      protocols           = "net.protocol in {%s}"
      http_methods        = ""
      dlp_profiles        = ""
      dns_locations       = ""
      upload_file_types   = ""
      download_file_types = ""
    })

    http = tomap({
      domains             = "any(http.request.domains[*] in {%s})"
      hosts               = "http.request.host in {%s}"
      sni_domains         = ""
      sni_hosts           = ""
      applications        = "any(app.ids[*] in {%s})"
      content_categories  = "any(http.request.uri.content_category[*] in {%s})"
      security_categories = "any(http.request.uri.security_category[*] in {%s})"
      destination_ips     = "any(http.conn.dst_ip[*] in {%s})"
      source_ips          = "any(http.conn.src_ip[*] in {%s})"
      destination_ports   = ""
      protocols           = ""
      http_methods        = "http.request.method in {%s}"
      dlp_profiles        = "any(dlp.profiles[*] in {%s})"
      dns_locations       = ""
      upload_file_types   = "any(http.upload.file.types[*] in {%s})"
      download_file_types = "any(http.download.file.types[*] in {%s})"
    })
  }

  # The same idea for list references, with `$%s` taking one list UUID. The
  # forms are the ones Cloudflare's own policy builder emits for "in list".
  list_field_templates = {
    dns = tomap({
      domain_lists         = "any(dns.domains[*] in $%s)"
      host_lists           = "dns.fqdn in $%s"
      sni_domain_lists     = ""
      sni_host_lists       = ""
      url_lists            = ""
      destination_ip_lists = "any(dns.resolved_ips[*] in $%s)"
      source_ip_lists      = "dns.src_ip in $%s"
    })

    network = tomap({
      domain_lists         = ""
      host_lists           = ""
      sni_domain_lists     = "any(net.sni.domains[*] in $%s)"
      sni_host_lists       = "net.sni.host in $%s"
      url_lists            = ""
      destination_ip_lists = "net.dst.ip in $%s"
      source_ip_lists      = "net.src.ip in $%s"
    })

    http = tomap({
      domain_lists         = "any(http.request.domains[*] in $%s)"
      host_lists           = "http.request.host in $%s"
      sni_domain_lists     = ""
      sni_host_lists       = ""
      url_lists            = "http.request.uri in $%s"
      destination_ip_lists = "http.conn.dst_ip in $%s"
      source_ip_lists      = "http.conn.src_ip in $%s"
    })
  }

  field_templates = {
    for type, templates in local.traffic_field_templates : type => merge(templates, local.list_field_templates[type])
  }

  selector_sets = {
    for key, policy in local.policies : key => tomap({
      domains             = join(" ", [for value in policy.match.domains : "\"${lower(trimspace(value))}\""])
      hosts               = join(" ", [for value in policy.match.hosts : "\"${lower(trimspace(value))}\""])
      sni_domains         = join(" ", [for value in policy.match.sni_domains : "\"${lower(trimspace(value))}\""])
      sni_hosts           = join(" ", [for value in policy.match.sni_hosts : "\"${lower(trimspace(value))}\""])
      applications        = join(" ", [for value in policy.match.application_ids : tostring(value)])
      content_categories  = join(" ", [for value in policy.match.content_category_ids : tostring(value)])
      security_categories = join(" ", [for value in policy.match.security_category_ids : tostring(value)])
      destination_ips     = join(" ", [for value in policy.match.destination_ip_cidrs : trimspace(value)])
      source_ips          = join(" ", [for value in policy.match.source_ip_cidrs : trimspace(value)])
      destination_ports   = join(" ", [for value in policy.match.destination_ports : tostring(value)])
      protocols           = join(" ", [for value in policy.match.protocols : "\"${lower(trimspace(value))}\""])
      http_methods        = join(" ", [for value in policy.match.http_methods : "\"${upper(trimspace(value))}\""])
      dlp_profiles        = join(" ", [for value in policy.match.dlp_profile_ids : "\"${trimspace(value)}\""])
      dns_locations       = join(" ", [for value in policy.match.dns_location_ids : "\"${trimspace(value)}\""])
      upload_file_types   = join(" ", [for value in policy.match.upload_file_types : "\"${lower(trimspace(value))}\""])
      download_file_types = join(" ", [for value in policy.match.download_file_types : "\"${lower(trimspace(value))}\""])
    })
  }

  list_selector_ids = {
    for key, policy in local.policies : key => tomap({
      domain_lists         = policy.match.domain_list_ids
      host_lists           = policy.match.host_list_ids
      sni_domain_lists     = policy.match.sni_domain_list_ids
      sni_host_lists       = policy.match.sni_host_list_ids
      url_lists            = policy.match.url_list_ids
      destination_ip_lists = policy.match.destination_ip_list_ids
      source_ip_lists      = policy.match.source_ip_list_ids
    })
  }

  # How many values each selector was given. This, not the compiled string, is
  # what every "is it set" decision below reads - see the header.
  selector_counts = {
    for key, policy in local.policies : key => tomap({
      domains              = length(policy.match.domains)
      hosts                = length(policy.match.hosts)
      sni_domains          = length(policy.match.sni_domains)
      sni_hosts            = length(policy.match.sni_hosts)
      applications         = length(policy.match.application_ids)
      content_categories   = length(policy.match.content_category_ids)
      security_categories  = length(policy.match.security_category_ids)
      destination_ips      = length(policy.match.destination_ip_cidrs)
      source_ips           = length(policy.match.source_ip_cidrs)
      destination_ports    = length(policy.match.destination_ports)
      protocols            = length(policy.match.protocols)
      http_methods         = length(policy.match.http_methods)
      dlp_profiles         = length(policy.match.dlp_profile_ids)
      dns_locations        = length(policy.match.dns_location_ids)
      upload_file_types    = length(policy.match.upload_file_types)
      download_file_types  = length(policy.match.download_file_types)
      domain_lists         = length(policy.match.domain_list_ids)
      host_lists           = length(policy.match.host_list_ids)
      sni_domain_lists     = length(policy.match.sni_domain_list_ids)
      sni_host_lists       = length(policy.match.sni_host_list_ids)
      url_lists            = length(policy.match.url_list_ids)
      destination_ip_lists = length(policy.match.destination_ip_list_ids)
      source_ip_lists      = length(policy.match.source_ip_list_ids)
    })
  }

  # A selector contributes a term when it was given values AND the policy type
  # has a field for it. The second half failing is reported, not silently
  # dropped - see unsupported_selectors.
  selector_active = {
    for key, policy in local.policies : key => tomap({
      for selector in local.all_selectors : selector => (
        local.selector_counts[key][selector] > 0 && local.field_templates[policy.type][selector] != ""
      )
    })
  }

  selector_terms = {
    for key, policy in local.policies : key => tomap({
      for selector in local.literal_selectors : selector => (
        local.selector_active[key][selector]
        ? format(local.traffic_field_templates[policy.type][selector], local.selector_sets[key][selector])
        : ""
      )
    })
  }

  list_terms = {
    for key, policy in local.policies : key => tomap({
      for selector in local.list_selectors : selector => (
        local.selector_active[key][selector]
        ? [for id in local.list_selector_ids[key][selector] : format(local.list_field_templates[policy.type][selector], trimspace(id))]
        : []
      )
    })
  }

  destination_clauses = {
    for key in local.policy_keys : key => concat(
      [
        for selector in local.destination_selectors : local.selector_terms[key][selector]
        if local.selector_active[key][selector]
      ],
      flatten([for selector in local.destination_list_selectors : local.list_terms[key][selector]]),
    )
  }

  file_clauses = {
    for key in local.policy_keys : key => [
      for selector in local.file_selectors : local.selector_terms[key][selector]
      if local.selector_active[key][selector]
    ]
  }

  # Literal source ranges and source IP lists name the same thing - where the
  # request came from - so they are OR'd into one constraint rather than AND'd
  # as two, which would demand a source in both at once.
  source_terms = {
    for key in local.policy_keys : key => concat(
      local.selector_active[key]["source_ips"] ? [local.selector_terms[key]["source_ips"]] : [],
      local.list_terms[key]["source_ip_lists"],
    )
  }

  constraint_clauses = {
    for key in local.policy_keys : key => concat(
      length(local.source_terms[key]) == 0 ? [] : [
        length(local.source_terms[key]) == 1
        ? local.source_terms[key][0]
        : "(${join(" or ", local.source_terms[key])})"
      ],
      [
        for selector in local.constraint_selectors : local.selector_terms[key][selector]
        if selector != "source_ips" && local.selector_active[key][selector]
      ],
    )
  }

  traffic_clauses = {
    for key in local.policy_keys : key => concat(
      length(local.destination_clauses[key]) == 0 ? [] : [
        length(local.destination_clauses[key]) == 1
        ? local.destination_clauses[key][0]
        : "(${join(" or ", local.destination_clauses[key])})"
      ],
      local.constraint_clauses[key],
      length(local.file_clauses[key]) == 0 ? [] : [
        length(local.file_clauses[key]) == 1
        ? local.file_clauses[key][0]
        : "(${join(" or ", local.file_clauses[key])})"
      ],
    )
  }

  compiled_traffic = {
    for key, policy in local.policies : key => (
      length(local.traffic_clauses[key]) == 0
      ? ""
      : (
        policy.match.negate
        ? "not (${join(" and ", local.traffic_clauses[key])})"
        : join(" and ", local.traffic_clauses[key])
      )
    )
  }

  # Identity terms are alternative ways of naming the same population, so they
  # are OR'd. A policy that named a group and an email and meant "both" wants two
  # policies, or a group that already expresses the intersection.
  identity_terms = {
    for key, policy in local.policies : key => concat(
      length(policy.identity.user_emails) == 0 ? [] : ["identity.email in {${join(" ", [for value in policy.identity.user_emails : "\"${lower(trimspace(value))}\""])}}"],
      length(policy.identity.user_group_names) == 0 ? [] : ["any(identity.groups[*].name in {${join(" ", [for value in policy.identity.user_group_names : "\"${trimspace(value)}\""])}})"],
      length(policy.identity.user_group_emails) == 0 ? [] : ["any(identity.groups[*].email in {${join(" ", [for value in policy.identity.user_group_emails : "\"${lower(trimspace(value))}\""])}})"],
      length(policy.identity.user_group_ids) == 0 ? [] : ["any(identity.groups[*].id in {${join(" ", [for value in policy.identity.user_group_ids : "\"${trimspace(value)}\""])}})"],
      [for id in policy.identity.user_email_list_ids : format("identity.email in $%s", trimspace(id))],
    )
  }

  compiled_identity = {
    for key in local.policy_keys : key => join(" or ", local.identity_terms[key])
  }

  compiled_device_posture = {
    for key, policy in local.policies : key => (
      length(policy.device_posture_check_ids) == 0
      ? ""
      : "any(device_posture.checks.passed[*] in {${join(" ", [for value in policy.device_posture_check_ids : "\"${trimspace(value)}\""])}})"
    )
  }

  # A hand-written expression replaces the compiled one entirely. It is not
  # merged, because merging would produce a rule nobody wrote.
  traffic = {
    for key, policy in local.policies : key => (
      policy.traffic_expression != null ? trimspace(policy.traffic_expression) : local.compiled_traffic[key]
    )
  }

  identity = {
    for key, policy in local.policies : key => (
      policy.identity_expression != null ? trimspace(policy.identity_expression) : local.compiled_identity[key]
    )
  }

  device_posture = {
    for key, policy in local.policies : key => (
      policy.device_posture_expression != null ? trimspace(policy.device_posture_expression) : local.compiled_device_posture[key]
    )
  }

  # Whether each dimension is sent at all. Decided from what was configured
  # rather than from the expression text, which may be unknown until apply.
  has_traffic = {
    for key, policy in local.policies : key => (
      policy.traffic_expression != null ? trimspace(policy.traffic_expression) != "" : length(local.traffic_clauses[key]) > 0
    )
  }

  has_identity = {
    for key, policy in local.policies : key => (
      policy.identity_expression != null ? trimspace(policy.identity_expression) != "" : length(local.identity_terms[key]) > 0
    )
  }

  has_device_posture = {
    for key, policy in local.policies : key => (
      policy.device_posture_expression != null ? trimspace(policy.device_posture_expression) != "" : length(policy.device_posture_check_ids) > 0
    )
  }

  # Provider-shaped rule_settings. Every policy carries the same attribute set so
  # the map has one type; unset settings are null and are not sent.
  rule_settings = {
    for key, policy in local.policies : key => (
      local.policies_with_settings[key]
      ? {
        block_reason       = policy.settings.block_reason
        block_page_enabled = policy.settings.block_page_enabled

        block_page = policy.settings.block_page == null ? null : {
          target_uri      = policy.settings.block_page.target_uri
          include_context = policy.settings.block_page.include_context
        }

        notification_settings = policy.settings.notification == null ? null : {
          enabled         = policy.settings.notification.enabled
          msg             = policy.settings.notification.msg
          support_url     = policy.settings.notification.support_url
          include_context = policy.settings.notification.include_context
        }

        redirect = policy.settings.redirect == null ? null : {
          target_uri              = policy.settings.redirect.target_uri
          include_context         = policy.settings.redirect.include_context
          preserve_path_and_query = policy.settings.redirect.preserve_path_and_query
        }

        check_session = policy.settings.check_session == null ? null : {
          duration = policy.settings.check_session.duration
          enforce  = policy.settings.check_session.enforce
        }

        l4override = policy.settings.l4_override == null ? null : {
          ip   = policy.settings.l4_override.ip
          port = policy.settings.l4_override.port
        }

        untrusted_cert = policy.settings.untrusted_cert_action == null ? null : {
          action = policy.settings.untrusted_cert_action
        }

        payload_log = policy.settings.payload_log_enabled == null ? null : {
          enabled = policy.settings.payload_log_enabled
        }

        quarantine = policy.settings.quarantine_file_types == null ? null : {
          file_types = policy.settings.quarantine_file_types
        }

        override_host                      = policy.settings.override_host
        override_ips                       = policy.settings.override_ips
        insecure_disable_dnssec_validation = policy.settings.insecure_disable_dnssec_validation
        ip_categories                      = policy.settings.ip_categories
        ignore_cname_category_matches      = policy.settings.ignore_cname_category_matches
      }
      : null
    )
  }

  policies_with_settings = {
    for key, policy in local.policies : key => anytrue([
      policy.settings.block_reason != null,
      policy.settings.block_page_enabled != null,
      policy.settings.block_page != null,
      policy.settings.notification != null,
      policy.settings.redirect != null,
      policy.settings.check_session != null,
      policy.settings.l4_override != null,
      policy.settings.untrusted_cert_action != null,
      policy.settings.payload_log_enabled != null,
      policy.settings.quarantine_file_types != null,
      policy.settings.override_host != null,
      policy.settings.override_ips != null,
      policy.settings.insecure_disable_dnssec_validation != null,
      policy.settings.ip_categories != null,
      policy.settings.ignore_cname_category_matches != null,
    ])
  }

  # Cloudflare's filters list. One policy is one builder here; a rule that had to
  # appear in two would be two rules with two precedences and two audit trails.
  policy_filters = tomap({
    dns     = "dns"
    network = "l4"
    http    = "http"
  })

  # Derived assertions, consumed by the preconditions in main.tf

  # Actions Cloudflare accepts per builder. An action from the wrong builder is
  # accepted by the provider's own enum and rejected by the API at apply.
  valid_actions = {
    dns     = ["allow", "block", "override", "safesearch", "ytrestricted"]
    network = ["allow", "block", "l4_override"]
    http    = ["allow", "block", "off", "on", "scan", "noscan", "isolate", "noisolate", "quarantine", "redirect"]
  }

  invalid_actions = sort([
    for key, policy in local.policies : "${key} (type = \"${policy.type}\", action = \"${policy.action}\")"
    if !contains(local.valid_actions[policy.type], policy.action)
  ])

  unsupported_selectors = sort(distinct(flatten([
    for key, policy in local.policies : [
      for selector in local.all_selectors : "${key}.match.${contains(local.list_selectors, selector) ? "${trimsuffix(selector, "s")}_ids" : selector} on a ${policy.type} policy"
      if local.selector_counts[key][selector] > 0 && local.field_templates[policy.type][selector] == ""
    ]
  ])))

  # Gateway walks each builder separately, so it is tempting to scope precedence
  # per type. Cloudflare does not: gateway/rules is one collection and the
  # `filters` field is what separates DNS from network from HTTP, so precedence
  # is allocated account-wide. Reusing a number across two types is rejected at
  # apply with 409 "A rule with this precedence already exists", and because
  # Terraform creates the policies concurrently, whichever one loses the race is
  # arbitrary. Checked across all policies for that reason.
  duplicate_precedences = sort(distinct([
    for policy in var.policies : "precedence ${policy.precedence}"
    if length([
      for other in var.policies : other
      if other.precedence == policy.precedence
    ]) > 1
  ]))

  policies_with_no_selector = sort([
    for key in local.policy_keys : key
    if !local.has_traffic[key] && !local.has_identity[key] && !local.has_device_posture[key] && !local.policies[key].match_all_traffic
  ])

  # A catch-all whose action opens something rather than closing it. Gateway
  # stops at the first allow it matches, so an unscoped allow is not "permissive
  # by default" - it is every policy below it deleted.
  unscoped_permissive_policies = sort([
    for key, policy in local.policies : "${key} (action = \"${policy.action}\")"
    if policy.match_all_traffic && contains(["allow", "off", "noscan", "noisolate"], policy.action)
  ])

  # Do Not Inspect is evaluated before TLS decryption, so it can only see what is visible in the TLS handshake.
  # A URL list is matched on the path as well as the host, and the path is inside the encrypted request.
  decryption_only_selectors = ["dlp_profiles", "http_methods", "upload_file_types", "download_file_types", "url_lists"]

  do_not_inspect_needing_decryption = sort(distinct(flatten([
    for key, policy in local.policies : [
      for selector in local.decryption_only_selectors : "${key}.match.${selector == "url_lists" ? "url_list_ids" : selector}"
      if policy.action == "off" && local.selector_counts[key][selector] > 0
    ]
  ])))

  # A DLP match is produced by scanning the request body. An action that turns
  # scanning off cannot act on one.
  dlp_with_incompatible_action = sort([
    for key, policy in local.policies : "${key} (action = \"${policy.action}\")"
    if length(policy.match.dlp_profile_ids) > 0 && contains(["off", "noscan"], policy.action)
  ])

  # Both a compiled matcher and a hand-written expression. One of them would be
  # discarded, and the plan gives no sign which.
  conflicting_traffic_definitions = sort([
    for key, policy in local.policies : key
    if policy.traffic_expression != null && length(local.traffic_clauses[key]) > 0
  ])

  conflicting_identity_definitions = sort([
    for key, policy in local.policies : key
    if policy.identity_expression != null && length(local.identity_terms[key]) > 0
  ])

  conflicting_device_posture_definitions = sort([
    for key, policy in local.policies : key
    if policy.device_posture_expression != null && local.compiled_device_posture[key] != ""
  ])

  # Actions Cloudflare will not apply without a setting to go with them.
  actions_missing_settings = sort(compact([
    for key, policy in local.policies : (
      policy.action == "redirect" && policy.settings.redirect == null ? "${key} needs settings.redirect" :
      policy.action == "quarantine" && policy.settings.quarantine_file_types == null ? "${key} needs settings.quarantine_file_types" :
      policy.action == "l4_override" && policy.settings.l4_override == null ? "${key} needs settings.l4_override" :
      policy.action == "override" && policy.settings.override_host == null && policy.settings.override_ips == null ? "${key} needs settings.override_host or settings.override_ips" :
      ""
    )
  ]))

  # Settings the builder in question does not have. Cloudflare drops them, so the
  # dashboard shows a policy configured one way and enforces it another.
  dns_only_settings = sort(distinct(flatten([
    for key, policy in local.policies : compact([
      policy.settings.insecure_disable_dnssec_validation != null ? "${key}.settings.insecure_disable_dnssec_validation" : "",
      policy.settings.ip_categories != null ? "${key}.settings.ip_categories" : "",
      policy.settings.ignore_cname_category_matches != null ? "${key}.settings.ignore_cname_category_matches" : "",
      policy.settings.override_host != null ? "${key}.settings.override_host" : "",
      policy.settings.override_ips != null ? "${key}.settings.override_ips" : "",
      policy.settings.block_page_enabled != null ? "${key}.settings.block_page_enabled" : "",
    ])
    if policy.type != "dns"
  ])))

  http_only_settings = sort(distinct(flatten([
    for key, policy in local.policies : compact([
      policy.settings.payload_log_enabled != null ? "${key}.settings.payload_log_enabled" : "",
      policy.settings.quarantine_file_types != null ? "${key}.settings.quarantine_file_types" : "",
      policy.settings.untrusted_cert_action != null ? "${key}.settings.untrusted_cert_action" : "",
      policy.settings.block_page != null ? "${key}.settings.block_page" : "",
      policy.settings.redirect != null ? "${key}.settings.redirect" : "",
    ])
    if policy.type != "http"
  ])))

  network_only_settings = sort(distinct(flatten([
    for key, policy in local.policies : compact([
      policy.settings.l4_override != null ? "${key}.settings.l4_override" : "",
    ])
    if policy.type != "network"
  ])))

  # Evaluation order per builder, for the outputs. sort() is lexicographic, so
  # the precedence is zero-padded before it is sorted and stripped again -
  # otherwise precedence 100 would sort ahead of precedence 20.
  ordered_policy_keys_by_type = {
    for type in keys(local.valid_actions) : type => [
      for entry in sort([
        for key, policy in local.policies : format("%09d|%s", policy.precedence, key)
        if policy.type == type
      ]) : split("|", entry)[1]
    ]
  }

  # Payload logging stores the matched content itself. Surfaced as a list so the
  # layer can decide whether the account permits it.
  policies_logging_dlp_payloads = sort([
    for key, policy in local.policies : key
    if try(policy.settings.payload_log_enabled, false) == true
  ])
}
