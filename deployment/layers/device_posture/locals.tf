# Applies the platform baseline, resolves integration keys, merges in the
# pipeline-supplied credentials and derives the preflight assertions, so that
# device_posture.tf reads as a plain module call.

locals {
  s2s_rule_types = [
    "intune", "crowdstrike_s2s", "kolide", "sentinelone_s2s",
    "tanium_s2s", "workspace_one", "custom_s2s",
  ]

  # Checks the Cloudflare One Client polls on the device. warp, gateway and the
  # legacy tanium check are not offered a schedule in the dashboard, so none is
  # sent for them unless the account tree sets one.
  scheduled_rule_types = [
    "os_version", "disk_encryption", "firewall", "antivirus", "domain_joined",
    "file", "application", "serial_number", "unique_client_id",
    "client_certificate", "client_certificate_v2", "sentinelone", "carbonblack",
  ]

  integration_names_by_key = { for key, integration in var.device_posture_integrations : key => integration.name }

  integration_intervals = {
    for key, integration in var.device_posture_integrations : key => coalesce(integration.interval, var.default_integration_interval)
  }

  # Module inputs

  # The credentials are merged in from the pipeline environment, never from a
  # file. A field the integration's type does not use is simply null.
  integrations = [
    for key, integration in var.device_posture_integrations : {
      name     = integration.name
      type     = integration.type
      interval = local.integration_intervals[key]
      config = {
        api_url              = integration.config.api_url
        auth_url             = integration.config.auth_url
        client_id            = integration.config.client_id
        customer_id          = integration.config.customer_id
        access_client_id     = integration.config.access_client_id
        client_secret        = try(var.device_posture_integration_secrets[key].client_secret, null)
        client_key           = try(var.device_posture_integration_secrets[key].client_key, null)
        access_client_secret = try(var.device_posture_integration_secrets[key].access_client_secret, null)
      }
    }
  ]

  # How often each rule's result is refreshed: the integration's interval for a
  # service provider check, the client schedule for a device check. Null where
  # this layer cannot know - an integration managed elsewhere.
  rule_polling_periods = {
    for key, rule in var.device_posture_rules : key => (
      contains(local.s2s_rule_types, rule.type)
      ? lookup(local.integration_intervals, coalesce(rule.integration_key, "-"), null)
      : contains(local.scheduled_rule_types, rule.type) ? coalesce(rule.schedule, var.default_posture_schedule) : rule.schedule
    )
  }

  # Durations are one unit of m or h - the module validates that - so doubling
  # keeps the unit, and what is sent reads the way Cloudflare stores it.
  derived_expirations = {
    for key, period in local.rule_polling_periods : key => try(
      "${tonumber(regex("^([0-9]+)(m|h)$", period)[0]) * 2}${regex("^([0-9]+)(m|h)$", period)[1]}",
      null,
    )
  }

  rules = [
    for key, rule in var.device_posture_rules : {
      name             = rule.name
      type             = rule.type
      description      = rule.description
      schedule         = contains(local.scheduled_rule_types, rule.type) ? coalesce(rule.schedule, var.default_posture_schedule) : rule.schedule
      expiration       = rule.expiration != null ? rule.expiration : (var.derive_posture_expiration ? local.derived_expirations[key] : null)
      platforms        = rule.platforms
      integration_name = rule.integration_key == null ? null : lookup(local.integration_names_by_key, rule.integration_key, null)
      integration_id   = rule.integration_id
      input            = rule.input
    }
  ]

  # Derived assertions, consumed by preflight.tf

  unknown_integration_keys = sort([
    for key, rule in var.device_posture_rules : "device_posture_rules.${key}.integration_key -> \"${rule.integration_key}\""
    if rule.integration_key != null && !contains(keys(var.device_posture_integrations), coalesce(rule.integration_key, "-"))
  ])

  # What each integration type needs to connect, from Cloudflare's setup guide
  # for each provider. A missing field is accepted by the API and fails
  # Cloudflare's connection test at apply, after the plan has been approved.
  integration_required_config = {
    intune          = ["client_id", "customer_id"]
    crowdstrike_s2s = ["client_id", "customer_id", "api_url"]
    kolide          = []
    sentinelone_s2s = ["api_url"]
    tanium_s2s      = ["api_url"]
    workspace_one   = ["client_id", "api_url", "auth_url"]
    uptycs          = ["customer_id"]
    custom_s2s      = ["api_url", "access_client_id"]
  }

  integration_required_secrets = {
    intune          = ["client_secret"]
    crowdstrike_s2s = ["client_secret"]
    kolide          = ["client_secret"]
    sentinelone_s2s = ["client_secret"]
    tanium_s2s      = ["client_secret"]
    workspace_one   = ["client_secret"]
    uptycs          = ["client_key", "client_secret"]
    custom_s2s      = ["access_client_secret"]
  }

  integrations_missing_config = sort(flatten([
    for key, integration in var.device_posture_integrations : [
      for field in lookup(local.integration_required_config, integration.type, []) :
      "device_posture_integrations.${key}.config.${field} (${integration.type})"
      if trimspace(coalesce(try(integration.config[field], null), " ")) == ""
    ]
  ]))

  # Which credential fields were supplied, as "key.field" - presence only,
  # never a value - so nothing sensitive reaches a precondition message.
  # sensitive() first because nonsensitive() refuses a value with no mark.
  supplied_secret_fields = nonsensitive(sensitive(flatten([
    for key, secret in var.device_posture_integration_secrets : [
      for field in ["client_secret", "client_key", "access_client_secret"] : "${key}.${field}"
      if try(trimspace(secret[field]), "") != ""
    ]
  ])))

  secret_keys = nonsensitive(keys(var.device_posture_integration_secrets))

  integrations_missing_secret = sort(flatten([
    for key, integration in var.device_posture_integrations : [
      for field in lookup(local.integration_required_secrets, integration.type, []) :
      "device_posture_integrations.${key} (${integration.type}) -> ${field}"
      if !contains(local.supplied_secret_fields, "${key}.${field}")
    ]
  ]))

  # A secret for no integration, or a field the integration's type never reads.
  orphaned_integration_secrets = sort(concat(
    [for key in local.secret_keys : key if !contains(keys(var.device_posture_integrations), key)],
    [
      for entry in local.supplied_secret_fields : entry
      if contains(keys(var.device_posture_integrations), split(".", entry)[0])
      && !contains(lookup(local.integration_required_secrets, try(var.device_posture_integrations[split(".", entry)[0]].type, ""), []), split(".", entry)[1])
    ],
  ))

  # enabled = false is not "check off" - it passes a device whose firewall is off.
  inverted_firewall_checks = sort([
    for key, rule in var.device_posture_rules : "device_posture_rules.${key}"
    if rule.type == "firewall" && rule.input.enabled == false
  ])

  # A file check for absence (exists = false) has no binary to sign.
  unsigned_binary_checks = !var.require_signed_binary_checks ? [] : sort([
    for key, rule in var.device_posture_rules : "device_posture_rules.${key} (${rule.type})"
    if contains(["file", "application", "sentinelone", "carbonblack"], rule.type)
    && trimspace(coalesce(rule.input.thumbprint, " ")) == ""
    && rule.input.exists != false
  ])

  expiration_seconds = {
    for key, rule in var.device_posture_rules : key => try(
      tonumber(regex("^([0-9]+)(m|h)$", rule.expiration)[0]) * (regex("^([0-9]+)(m|h)$", rule.expiration)[1] == "h" ? 3600 : 60),
      null,
    )
  }

  polling_seconds = {
    for key, period in local.rule_polling_periods : key => try(
      tonumber(regex("^([0-9]+)(m|h)$", period)[0]) * (regex("^([0-9]+)(m|h)$", period)[1] == "h" ? 3600 : 60),
      null,
    )
  }

  short_expirations = sort([
    for key, rule in var.device_posture_rules :
    "device_posture_rules.${key} (expiration ${rule.expiration}, refreshed every ${local.rule_polling_periods[key]})"
    if local.expiration_seconds[key] != null && local.polling_seconds[key] != null ? local.expiration_seconds[key] < 2 * local.polling_seconds[key] : false
  ])

  restricted_posture_rule_types = [for type in var.restricted_posture_rule_types : lower(trimspace(type))]

  restricted_types_used = sort([
    for key, rule in var.device_posture_rules : "device_posture_rules.${key} -> \"${rule.type}\""
    if contains(local.restricted_posture_rule_types, lower(rule.type))
  ])
}
