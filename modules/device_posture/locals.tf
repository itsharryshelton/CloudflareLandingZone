locals {
  # Collections, keyed on the Cloudflare-visible name
  integrations     = { for i in var.integrations : lower(trimspace(i.name)) => i }
  integration_keys = keys(local.integrations)

  rules = { for r in var.rules : lower(trimspace(r.name)) => r }

  integration_ids_by_name = {
    for key in local.integration_keys : key => cloudflare_zero_trust_device_posture_integration.this[key].id
  }

  # Normalised once, so a rule with no integration_name never reaches trimspace.
  integration_refs = {
    for key, rule in local.rules : key => rule.integration_name == null ? "" : lower(trimspace(rule.integration_name))
  }

  # A name that resolves to nothing becomes null here and is reported by a
  # precondition in main.tf, rather than failing as an invalid index.
  connection_ids = {
    for key, rule in local.rules : key => (
      rule.integration_id != null
      ? rule.integration_id
      : lookup(local.integration_ids_by_name, local.integration_refs[key], null)
    )
  }

  # Decided from the configuration alone. The connection ID of an integration
  # created in the same run is unknown at plan, and testing it here would make
  # the whole input unknown and hide it from the plan reviewer.
  rules_with_input = [
    for key, rule in local.rules : key
    if rule.integration_name != null || rule.integration_id != null || anytrue([for attr, value in rule.input : value != null])
  ]

  # Provider-shaped. list_id is the provider's `id`, renamed because a bare
  # "id" inside a rule reads as the rule's own. Kolide's deprecated issue_count
  # and count_operator are left out on purpose - see variables.tf.
  rule_inputs = {
    for key, rule in local.rules : key => !contains(local.rules_with_input, key) ? null : {
      operating_system          = rule.input.operating_system
      path                      = rule.input.path
      exists                    = rule.input.exists
      sha256                    = rule.input.sha256
      thumbprint                = rule.input.thumbprint
      id                        = rule.input.list_id
      domain                    = rule.input.domain
      operator                  = rule.input.operator
      version                   = rule.input.version
      os_distro_name            = rule.input.os_distro_name
      os_distro_revision        = rule.input.os_distro_revision
      os_version_extra          = rule.input.os_version_extra
      enabled                   = rule.input.enabled
      check_disks               = rule.input.check_disks
      require_all               = rule.input.require_all
      certificate_id            = rule.input.certificate_id
      cn                        = rule.input.cn
      check_private_key         = rule.input.check_private_key
      extended_key_usage        = rule.input.extended_key_usage
      subject_alternative_names = rule.input.subject_alternative_names
      locations                 = rule.input.locations
      update_window_days        = rule.input.update_window_days
      compliance_status         = rule.input.compliance_status
      connection_id             = local.connection_ids[key]
      last_seen                 = rule.input.last_seen
      os                        = rule.input.os
      overall                   = rule.input.overall
      sensor_config             = rule.input.sensor_config
      state                     = rule.input.state
      version_operator          = rule.input.version_operator
      auth_state                = rule.input.auth_state
      eid_last_seen             = rule.input.eid_last_seen
      risk_level                = rule.input.risk_level
      score_operator            = rule.input.score_operator
      total_score               = rule.input.total_score
      active_threats            = rule.input.active_threats
      infected                  = rule.input.infected
      is_active                 = rule.input.is_active
      network_status            = rule.input.network_status
      operational_state         = rule.input.operational_state
      score                     = rule.input.score
    }
  }

  rule_matches = {
    for key, rule in local.rules : key => length(rule.platforms) == 0 ? null : [
      for platform in distinct(rule.platforms) : { platform = platform }
    ]
  }

  # Derived assertions, consumed by the preconditions in main.tf

  unknown_integration_names = sort([
    for key, rule in local.rules : "rules.${key}.integration_name -> \"${rule.integration_name}\""
    if local.integration_refs[key] != "" && !contains(local.integration_keys, local.integration_refs[key])
  ])

  # Cloudflare accepts a rule pointed at another provider's integration and the
  # rule then never passes, because the attributes it asks for are never sent.
  mismatched_integration_types = sort([
    for key, rule in local.rules :
    "rules.${key} (${rule.type}) -> \"${local.integration_refs[key]}\" (${local.integrations[local.integration_refs[key]].type})"
    if contains(local.integration_keys, local.integration_refs[key]) ? local.integrations[local.integration_refs[key]].type != rule.type : false
  ])
}
