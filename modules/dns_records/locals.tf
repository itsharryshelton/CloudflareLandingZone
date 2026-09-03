locals {
  input_names = [
    for record in var.records : trimsuffix(lower(trimspace(record.name)), ".")
  ]

  # Cloudflare's API stores and returns DNS names fully-qualified. Sending a
  # relative name ("www") therefore reads back as "www.example.com" and shows
  # perpetual drift on every plan, so qualify every name up front. "@" is
  # accepted for the apex out of dashboard familiarity.
  records_normalised = [
    for idx, record in var.records : {
      name = (
        contains(["@", var.domain_name], local.input_names[idx])
        ? var.domain_name
        : endswith(local.input_names[idx], ".${var.domain_name}")
        ? local.input_names[idx]
        : "${local.input_names[idx]}.${var.domain_name}"
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

  # Key based, so re-ordering causes no destroy by accident
  records_grouped = {
    for record in local.records_normalised :
    "${record.type}/${record.name}/${record.content}" => record...
  }

  records = {
    for key, records in local.records_grouped : key => records[0]
  }

  duplicate_keys = [
    for key, records in local.records_grouped : key if length(records) > 1
  ]
}
