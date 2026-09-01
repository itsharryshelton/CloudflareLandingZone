locals {
  # Catalogues
  #
  # Cloudflare returns categories two levels deep - a parent such as "Security
  # Risks" and the subcategories under it - and a policy can name either, so both
  # levels are flattened into one lookup.

  # A category with no children returns `subcategories` as null rather than as an
  # empty list. `try` does not rescue that - null is a value, not an error - so
  # the nulls survive the flatten and have to be dropped here, or every read of
  # `subcategory.name` below fails on them.
  category_subcategories = [
    for subcategory in flatten([
      for category in data.cloudflare_zero_trust_gateway_categories_list.this.result :
      try(category.subcategories, [])
    ]) : subcategory
    if subcategory != null
  ]

  # Grouped before it is indexed: Cloudflare is free to ship the same name under
  # two parents, and a bare `for` would fail the plan on the duplicate key. A
  # subcategory still wins over a parent of the same name, as before.
  category_ids_by_name = merge(
    {
      for name, ids in {
        for category in data.cloudflare_zero_trust_gateway_categories_list.this.result :
        lower(trimspace(category.name)) => category.id...
      } : name => min(ids...)
    },
    {
      for name, ids in {
        for subcategory in local.category_subcategories :
        lower(trimspace(subcategory.name)) => subcategory.id...
      } : name => min(ids...)
    },
  )

  category_names = sort(distinct(concat(
    [for category in data.cloudflare_zero_trust_gateway_categories_list.this.result : trimspace(category.name)],
    [for subcategory in local.category_subcategories : trimspace(subcategory.name)],
  )))

  # Applications and app types come back in one list. `id` is the value
  # `app.ids` matches on.
  #
  # That one list makes names non-unique - an app type and an application beneath
  # it can share a name, and a rebrand can leave both the old and new entry - so
  # the names are grouped and the lowest id taken. Lowest rather than first
  # because the API does not promise an order, and an id that moved between plans
  # would show as drift on a rule nobody touched.
  application_ids_by_name = {
    for name, ids in {
      for application in data.cloudflare_zero_trust_gateway_app_types_list.this.result :
      lower(trimspace(application.name)) => application.id...
    } : name => min(ids...)
  }

  application_name_count = length(local.application_ids_by_name)

  # Baseline selection

  selected_baseline_keys = [
    for name in var.gateway_baseline_policies : name
    if contains(keys(local.gateway_baseline_catalogue), name)
  ]

  unsatisfied_baselines = sort([
    for key in local.selected_baseline_keys :
    "${key}: ${local.gateway_baseline_requirements[key].reason}"
    if !local.gateway_baseline_requirements[key].satisfied
  ])

  # Module inputs
  #
  # Both sources are rendered into the same flat shape the module takes, with
  # every attribute written out, because Terraform needs one element type across
  # the concatenated list.

  baseline_module_policies = [
    for key in local.selected_baseline_keys : {
      name              = local.gateway_baseline_catalogue[key].name
      type              = local.gateway_baseline_catalogue[key].type
      action            = local.gateway_baseline_catalogue[key].action
      precedence        = local.gateway_baseline_catalogue[key].precedence
      description       = local.gateway_baseline_catalogue[key].description
      enabled           = true
      match_all_traffic = false

      match = {
        negate      = false
        domains     = []
        hosts       = []
        sni_domains = []
        sni_hosts   = []

        application_ids = [
          for name in local.gateway_baseline_catalogue[key].applications : local.application_ids_by_name[lower(trimspace(name))]
          if contains(keys(local.application_ids_by_name), lower(trimspace(name)))
        ]

        content_category_ids = [
          for name in local.gateway_baseline_catalogue[key].content_categories : local.category_ids_by_name[lower(trimspace(name))]
          if contains(keys(local.category_ids_by_name), lower(trimspace(name)))
        ]

        security_category_ids = [
          for name in local.gateway_baseline_catalogue[key].security_categories : local.category_ids_by_name[lower(trimspace(name))]
          if contains(keys(local.category_ids_by_name), lower(trimspace(name)))
        ]

        destination_ip_cidrs = []
        source_ip_cidrs      = []
        destination_ports    = []
        protocols            = []
        http_methods         = []
        dlp_profile_ids      = local.gateway_baseline_catalogue[key].dlp_profile_ids
        upload_file_types    = []
        download_file_types  = local.gateway_baseline_catalogue[key].download_file_types
      }

      identity = {
        user_emails       = []
        user_group_names  = []
        user_group_emails = []
        user_group_ids    = []
      }

      device_posture_check_ids  = []
      traffic_expression        = null
      identity_expression       = null
      device_posture_expression = null
      schedule                  = null
      expiration                = null

      settings = {
        block_reason       = local.gateway_baseline_catalogue[key].block_reason
        block_page_enabled = local.gateway_baseline_catalogue[key].block_page_enabled
        block_page         = null

        notification = (
          local.gateway_baseline_catalogue[key].action == "block" && var.default_block_notification != null
          ? {
            enabled         = var.default_block_notification.enabled
            msg             = var.default_block_notification.msg
            support_url     = var.default_block_notification.support_url
            include_context = null
          }
          : null
        )

        redirect              = null
        check_session         = null
        l4_override           = null
        untrusted_cert_action = null
        payload_log_enabled   = null
        quarantine_file_types = local.gateway_baseline_catalogue[key].quarantine_file_types

        override_host                      = null
        override_ips                       = null
        insecure_disable_dnssec_validation = null
        ip_categories                      = null
        ignore_cname_category_matches      = null
      }
    }
  ]

  operator_module_policies = [
    for key, policy in var.gateway_policies : {
      name              = policy.name
      type              = policy.type
      action            = policy.action
      precedence        = policy.precedence
      description       = policy.description
      enabled           = policy.enabled
      match_all_traffic = policy.match_all_traffic

      match = {
        negate      = policy.match.negate
        domains     = policy.match.domains
        hosts       = policy.match.hosts
        sni_domains = policy.match.sni_domains
        sni_hosts   = policy.match.sni_hosts

        application_ids = [
          for name in policy.match.applications : local.application_ids_by_name[lower(trimspace(name))]
          if contains(keys(local.application_ids_by_name), lower(trimspace(name)))
        ]

        content_category_ids = [
          for name in policy.match.content_categories : local.category_ids_by_name[lower(trimspace(name))]
          if contains(keys(local.category_ids_by_name), lower(trimspace(name)))
        ]

        security_category_ids = [
          for name in policy.match.security_categories : local.category_ids_by_name[lower(trimspace(name))]
          if contains(keys(local.category_ids_by_name), lower(trimspace(name)))
        ]

        destination_ip_cidrs = policy.match.destination_ip_cidrs
        source_ip_cidrs      = policy.match.source_ip_cidrs
        destination_ports    = policy.match.destination_ports
        protocols            = policy.match.protocols
        http_methods         = policy.match.http_methods
        dlp_profile_ids      = policy.match.dlp_profile_ids
        upload_file_types    = policy.match.upload_file_types
        download_file_types  = policy.match.download_file_types
      }

      identity = {
        user_emails       = policy.identity.user_emails
        user_group_names  = policy.identity.user_group_names
        user_group_emails = policy.identity.user_group_emails
        user_group_ids    = policy.identity.user_group_ids
      }

      device_posture_check_ids  = policy.device_posture_check_ids
      traffic_expression        = policy.traffic_expression
      identity_expression       = policy.identity_expression
      device_posture_expression = policy.device_posture_expression
      schedule                  = policy.schedule
      expiration                = policy.expiration

      settings = {
        block_reason       = policy.settings.block_reason
        block_page_enabled = policy.settings.block_page_enabled
        block_page         = policy.settings.block_page

        # The platform notification is a fallback, not an override: a policy that
        # wrote its own message keeps it.
        notification = (
          policy.settings.notification != null
          ? policy.settings.notification
          : (
            policy.action == "block" && var.default_block_notification != null
            ? {
              enabled         = var.default_block_notification.enabled
              msg             = var.default_block_notification.msg
              support_url     = var.default_block_notification.support_url
              include_context = null
            }
            : null
          )
        )

        redirect      = policy.settings.redirect
        check_session = policy.settings.check_session
        l4_override   = policy.settings.l4_override

        # Declared on every HTTP allow policy rather than left to Cloudflare's
        # default, so a dashboard change shows up as drift on the next plan.
        untrusted_cert_action = (
          policy.settings.untrusted_cert_action != null
          ? policy.settings.untrusted_cert_action
          : (policy.type == "http" && policy.action == "allow" ? var.default_untrusted_cert_action : null)
        )

        payload_log_enabled   = policy.settings.payload_log_enabled
        quarantine_file_types = policy.settings.quarantine_file_types

        override_host                      = policy.settings.override_host
        override_ips                       = policy.settings.override_ips
        insecure_disable_dnssec_validation = policy.settings.insecure_disable_dnssec_validation
        ip_categories                      = policy.settings.ip_categories
        ignore_cname_category_matches      = policy.settings.ignore_cname_category_matches
      }
    }
  ]

  gateway_policies = concat(local.baseline_module_policies, local.operator_module_policies)

  # Derived assertions, consumed by preflight.tf

  # Every place a category is named, gathered so one message covers all of them.
  category_name_references = flatten([
    [
      for key in local.selected_baseline_keys : concat(
        [for name in local.gateway_baseline_catalogue[key].security_categories : "gateway_security_categories -> \"${name}\"" if !contains(keys(local.category_ids_by_name), lower(trimspace(name)))],
        [for name in local.gateway_baseline_catalogue[key].content_categories : "gateway_blocked_content_categories -> \"${name}\"" if !contains(keys(local.category_ids_by_name), lower(trimspace(name)))],
      )
    ],
    [
      for key, policy in var.gateway_policies : concat(
        [for name in policy.match.security_categories : "gateway_policies.${key}.match.security_categories -> \"${name}\"" if !contains(keys(local.category_ids_by_name), lower(trimspace(name)))],
        [for name in policy.match.content_categories : "gateway_policies.${key}.match.content_categories -> \"${name}\"" if !contains(keys(local.category_ids_by_name), lower(trimspace(name)))],
      )
    ],
  ])

  unknown_category_names = sort(distinct(local.category_name_references))

  application_name_references = flatten([
    [
      for key in local.selected_baseline_keys : [
        for name in local.gateway_baseline_catalogue[key].applications : "gateway_bypass_applications -> \"${name}\""
        if !contains(keys(local.application_ids_by_name), lower(trimspace(name)))
      ]
    ],
    [
      for key, policy in var.gateway_policies : [
        for name in policy.match.applications : "gateway_policies.${key}.match.applications -> \"${name}\""
        if !contains(keys(local.application_ids_by_name), lower(trimspace(name)))
      ]
    ],
  ])

  unknown_application_names = sort(distinct(local.application_name_references))

  # The same unresolved names, unformatted, so they can be matched against the
  # catalogue below.
  unresolved_application_names = distinct(flatten([
    [
      for key in local.selected_baseline_keys : [
        for name in local.gateway_baseline_catalogue[key].applications : lower(trimspace(name))
        if !contains(keys(local.application_ids_by_name), lower(trimspace(name)))
      ]
    ],
    [
      for key, policy in var.gateway_policies : [
        for name in policy.match.applications : lower(trimspace(name))
        if !contains(keys(local.application_ids_by_name), lower(trimspace(name)))
      ]
    ],
  ]))

  # Catalogue entries sharing a word with something that did not resolve. The
  # catalogue runs past 1500 entries and is not printable, and the names are not
  # the ones the SaaS application selector shows, so a bare "no match" leaves an
  # operator guessing. Words of three characters or fewer are skipped because
  # "365" and "ID" match most of the catalogue.
  application_name_suggestions = slice(
    sort(distinct([
      for candidate in keys(local.application_ids_by_name) : candidate
      if anytrue([
        for name in local.unresolved_application_names :
        anytrue([for word in split(" ", name) : strcontains(candidate, word) if length(word) > 3])
      ])
    ])),
    0,
    min(40, length(distinct([
      for candidate in keys(local.application_ids_by_name) : candidate
      if anytrue([
        for name in local.unresolved_application_names :
        anytrue([for word in split(" ", name) : strcontains(candidate, word) if length(word) > 3])
      ])
    ])))
  )

  # The baseline occupies the low precedences on purpose. Gateway stops at the
  # first allow or block that matches, so an account tree rule in front of a
  # platform block is a platform block that never runs.
  reserved_precedence_violations = sort([
    for key, policy in var.gateway_policies : "gateway_policies.${key} (type = \"${policy.type}\", precedence = ${policy.precedence})"
    if policy.precedence < var.reserved_precedence_ceiling
  ])

  restricted_actions = [for action in var.restricted_actions : lower(trimspace(action))]

  restricted_actions_used = sort([
    for key, policy in var.gateway_policies : "gateway_policies.${key} -> \"${policy.action}\""
    if contains(local.restricted_actions, lower(trimspace(policy.action)))
  ])

  restricted_baseline_actions_used = sort([
    for key in local.selected_baseline_keys : "${key} -> \"${local.gateway_baseline_catalogue[key].action}\""
    if contains(local.restricted_actions, lower(trimspace(local.gateway_baseline_catalogue[key].action)))
  ])

  dlp_payload_logging_used = sort([
    for key, policy in var.gateway_policies : "gateway_policies.${key}"
    if try(policy.settings.payload_log_enabled, false) == true
  ])

  dnssec_validation_disabled = sort([
    for key, policy in var.gateway_policies : "gateway_policies.${key}"
    if try(policy.settings.insecure_disable_dnssec_validation, false) == true
  ])

  # An HTTP policy is only consulted for a request Gateway decrypted. With
  # inspection off - or with the account configuration unmanaged, where it may
  # be off and nothing here would know - those policies apply to plaintext HTTP
  # alone while the dashboard lists them as active. "off" (Do Not Inspect) is
  # excluded: it is evaluated on the handshake, so it is merely redundant rather
  # than broken.
  tls_decrypt_state = var.gateway_settings == null ? "unmanaged" : tostring(try(var.gateway_settings.tls_decrypt.enabled, "unset"))

  uninspected_http_policies = local.tls_decrypt_state == "true" ? [] : sort([
    for key, policy in var.gateway_policies : "gateway_policies.${key} (action = \"${policy.action}\")"
    if policy.type == "http" && policy.action != "off"
  ])

  untrusted_cert_pass_through_used = sort(concat(
    [
      for key, policy in var.gateway_policies : "gateway_policies.${key}"
      if try(policy.settings.untrusted_cert_action, "") == "pass_through"
    ],
    var.default_untrusted_cert_action == "pass_through" ? ["default_untrusted_cert_action"] : [],
  ))
}
