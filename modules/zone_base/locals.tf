locals {
  # Zone settings

  # The secure baseline. It lives here rather than as var.zone_settings' default
  # because a caller that sets zone_settings at all replaces that default
  zone_settings_baseline = {
    automatic_https_rewrites = "on"
    opportunistic_encryption = "on"
    browser_check            = "on"
    http3                    = "on"
  }

  # Baseline, then caller overrides, then the dedicated variables - which win
  # over anything supplied through var.zone_settings.
  zone_settings = merge(
    local.zone_settings_baseline,
    var.zone_settings,
    {
      ssl              = var.ssl_mode
      min_tls_version  = var.min_tls_version
      tls_1_3          = var.tls_1_3
      always_use_https = var.always_use_https
    }
  )

  # DNS records
  dns_input_names = [
    for record in var.dns_records : trimsuffix(lower(trimspace(record.name)), ".")
  ]

  # Cloudflare's API stores and returns DNS names fully-qualified. Sending a
  # relative name ("www") therefore reads back as "www.example.com" and shows
  # perpetual drift on every plan, so qualify every name up front. "@" is
  # accepted for the apex out of dashboard familiarity.
  dns_records_normalised = [
    for idx, record in var.dns_records : {
      name = (
        contains(["@", var.domain_name], local.dns_input_names[idx])
        ? var.domain_name
        : endswith(local.dns_input_names[idx], ".${var.domain_name}")
        ? local.dns_input_names[idx]
        : "${local.dns_input_names[idx]}.${var.domain_name}"
      )
      type     = upper(record.type)
      content  = record.content
      ttl      = record.ttl
      proxied  = record.proxied
      priority = record.priority
      comment  = record.comment
      tags     = record.tags
    }
  ]

  # Stable, unique key per record so reordering the input list never forces a
  # replacement. type+name+content is unique for well-formed record sets.
  dns_records_grouped = {
    for record in local.dns_records_normalised :
    "${record.type}/${record.name}/${record.content}" => record...
  }

  dns_records = {
    for key, records in local.dns_records_grouped : key => records[0]
  }

  dns_record_duplicate_keys = [
    for key, records in local.dns_records_grouped : key if length(records) > 1
  ]
}
