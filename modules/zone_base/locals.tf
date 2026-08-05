# ---------------------------------------------------------------------------
# Normalisation and keying for everything the operator supplies via variables.
#
# All of the "make the operator-facing schema safe" logic lives here so that
# main.tf only ever consumes already-normalised, provider-shaped values. Cheap
# structural guarantees (types, enums, required fields) are enforced by
# validation blocks in variables.tf; anything that needs cross-field or
# cross-record reasoning is derived here and asserted with a precondition in
# main.tf.
# ---------------------------------------------------------------------------

locals {
  # -------------------------------------------------------------------------
  # Zone settings
  # -------------------------------------------------------------------------

  # Secure baseline + caller overrides. The dedicated ssl_mode / min_tls_version
  # variables win over anything supplied through var.zone_settings.
  zone_settings = merge(
    var.zone_settings,
    {
      ssl             = var.ssl_mode
      min_tls_version = var.min_tls_version
    }
  )

  # -------------------------------------------------------------------------
  # DNS records
  # -------------------------------------------------------------------------

  # NOTE: the set of proxiable record types (A, AAAA, CNAME) is enforced by a
  # validation block in variables.tf rather than a local here, because variable
  # validation cannot reference locals.

  # Lower-cased, whitespace- and trailing-dot-trimmed input names, positionally
  # aligned with var.dns_records.
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
  #
  # Grouped with `...` deliberately: a plain `for` object expression aborts with
  # Terraform's generic "Duplicate object key" error pointing into this file,
  # which tells the operator nothing useful. Grouping keeps evaluation alive so
  # main.tf can fail the plan with an actionable message instead.
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
