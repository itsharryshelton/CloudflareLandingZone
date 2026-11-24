# Joins the zone inventory to its certificate configuration, applies the
# platform defaults, hands each zone only the custom certificate material its
# own entries name, and derives the preflight assertions - so certificates.tf
# reads as a plain module call.

locals {
  # var.custom_certificates is sensitive, so only its KEYS are ever unmarked,
  # and only after sensitive() has guaranteed a mark for nonsensitive() to strip
  # - an empty map carries none. No PEM and no private key is unmarked anywhere
  # in this layer.
  supplied_certificate_keys = nonsensitive(sensitive(sort(keys(var.custom_certificates))))

  # A zone key with no entry is not configured by this layer at all. A key with
  # no matching zone is an operator error, reported by preflight.tf rather than
  # silently dropped here.
  managed_zones = {
    for key, config in var.certificates : key => config
    if contains(keys(var.zones), key)
  }

  # Module inputs, one entry per zone.
  certificates = {
    for key, config in local.managed_zones : key => {
      domain_name   = var.zones[key].domain_name
      universal_ssl = config.universal_ssl
      total_tls     = config.total_tls

      certificate_packs = {
        for name, pack in config.certificate_packs : name => {
          hosts                 = pack.hosts
          certificate_authority = coalesce(pack.certificate_authority, var.default_certificate_authority)
          validation_method     = coalesce(pack.validation_method, var.default_validation_method)
          validity_days         = coalesce(pack.validity_days, var.default_validity_days)
          cloudflare_branding   = pack.cloudflare_branding
        }
      }

      custom_certificates = {
        for name, cert in config.custom_certificates : name => {
          bundle_method   = coalesce(cert.bundle_method, var.default_bundle_method)
          type            = cert.type
          geo_restriction = cert.geo_restriction
        }
      }

      # Keyed by the entry, not the certificate_key, because that is how the
      # module pairs material with settings. A certificate_key naming nothing
      # supplied is dropped here and reported by preflight.tf, then again by
      # the module as an entry without material.
      custom_certificate_material = {
        for name, cert in config.custom_certificates :
        name => var.custom_certificates[cert.certificate_key]
        if contains(local.supplied_certificate_keys, cert.certificate_key)
      }

      origin_ca_certificates = {
        for name, cert in config.origin_ca_certificates : name => {
          hostnames          = cert.hostnames
          csr                = cert.csr
          request_type       = cert.request_type
          requested_validity = coalesce(cert.requested_validity, var.default_origin_ca_validity_days)
        }
      }
    }
  }

  # Derived assertions, consumed by preflight.tf

  orphaned_certificate_keys = sort([
    for key in keys(var.certificates) : key
    if !contains(keys(var.zones), key)
  ])

  certificate_references = flatten([
    for key, config in local.managed_zones : [
      for name, cert in config.custom_certificates : {
        where           = "certificates.${key}.custom_certificates.${name}.certificate_key"
        certificate_key = cert.certificate_key
      }
    ]
  ])

  referenced_certificate_keys = distinct([
    for reference in local.certificate_references : reference.certificate_key
  ])

  missing_certificates = sort([
    for reference in local.certificate_references : "${reference.where} -> \"${reference.certificate_key}\""
    if !contains(local.supplied_certificate_keys, reference.certificate_key)
  ])

  orphaned_certificates = sort([
    for certificate_key in local.supplied_certificate_keys : certificate_key
    if !contains(local.referenced_certificate_keys, certificate_key)
  ])

  # Read from the zone itself rather than the declared zone_tier: the quota is
  # what Cloudflare will enforce, and it is 0 on Free and Pro. try() because a
  # zone the provider returns without meta has nothing to compare against.
  over_quota_zones = sort([
    for key, config in local.managed_zones :
    "certificates.${key} (${length(config.custom_certificates)} custom certificates, quota ${data.cloudflare_zone.this[key].meta.custom_certificate_quota})"
    if length(config.custom_certificates) > 0
    && try(data.cloudflare_zone.this[key].meta.custom_certificate_quota != null, false)
    && length(config.custom_certificates) > try(data.cloudflare_zone.this[key].meta.custom_certificate_quota, 0)
  ])

  # Total TLS is only offered on a full DNS setup: on a partial one Cloudflare
  # cannot see which records are proxied in order to cover them.
  total_tls_not_full_setup = sort([
    for key, config in local.managed_zones :
    "certificates.${key} (${var.zones[key].domain_name}, setup type \"${data.cloudflare_zone.this[key].type}\")"
    if try(config.total_tls.enabled, false)
    && try(data.cloudflare_zone.this[key].type, "full") != "full"
  ])
}
