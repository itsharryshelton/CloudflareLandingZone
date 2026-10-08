locals {
  # Zone settings

  # The secure baseline. It lives here rather than as var.zone_settings' default
  # because a caller that sets zone_settings at all replaces that default
  #
  # Every entry costs one cloudflare_zone_setting resource per zone, and one
  # Cloudflare API read per zone on every refresh, against a budget of 1200
  # requests per 5 minutes per credential. A caller with a few hundred zones
  # therefore pays for this map several hundred times over on each plan, so the
  # bar for being in it is that Terraform asserting the value defends something
  # - not merely that the value is the one we want.
  #
  # Kept:
  #   automatic_https_rewrites  rewrites HTTP subresources to HTTPS, so it is
  #                             part of the mixed-content posture the ssl and
  #                             always_use_https settings below establish.
  #   browser_check             a threat control. If someone turns it off in the
  #                             dashboard, the fleet should pull it back on.
  #
  # Removed, both of which are "on" by Cloudflare default on every plan and
  # neither of which is a security control:
  #   opportunistic_encryption  upgrades HTTP clients that advertise support. No
  #                             posture is lost by not asserting it, because
  #                             always_use_https redirects those clients anyway.
  #   http3                     a transport performance feature.
  #
  # Removing a setting plans a destroy for it. cloudflare_zone_setting has no
  # delete operation - the provider's Delete is an empty function - so that
  # drops the resource from state and leaves the value untouched at Cloudflare.
  # A caller that wants either back can set it in var.zone_settings.
  zone_settings_baseline = {
    automatic_https_rewrites = "on"
    browser_check            = "on"
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

  # Record types whose content is a hostname rather than free text.
  dns_hostname_content_types = ["CNAME", "MX", "NS", "PTR"]

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
      type = upper(record.type)
      # Cloudflare rewrites a hostname target on write: "@" becomes the apex and
      # the name is lowercased. Sending it as written therefore reads back
      # different, and the record shows an update on every plan that no apply
      # ever settles. Other types are left alone - TXT content is case-sensitive.
      content = (
        !contains(local.dns_hostname_content_types, upper(record.type))
        ? record.content
        : trimspace(record.content) == "@"
        ? var.domain_name
        : lower(record.content)
      )
      # Content as written, kept only to build the state key from - see
      # dns_records_grouped.
      key_content = record.content
      ttl         = record.ttl
      proxied     = record.proxied
      priority    = record.priority
      comment     = record.comment
      tags        = record.tags
    }
  ]

  # Stable, unique key per record so reordering the input list never forces a
  # replacement. type+name+content is unique for well-formed record sets.
  #
  # The key uses the content as written rather than as sent: keying on the
  # normalised content would destroy and recreate every record whose target was
  # written as "@" or in upper case.
  dns_records_grouped = {
    for record in local.dns_records_normalised :
    "${record.type}/${record.name}/${record.key_content}" => record...
  }

  dns_records = {
    for key, records in local.dns_records_grouped : key => records[0]
  }

  dns_record_duplicate_keys = [
    for key, records in local.dns_records_grouped : key if length(records) > 1
  ]
}
