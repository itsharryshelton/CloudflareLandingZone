# Joins the zone inventory to its Authenticated Origin Pulls configuration,
# hands each zone only the certificates its own entries name, and derives the
# preflight assertions - so origin_pulls.tf reads as a plain module call.

locals {
  # var.origin_pull_certificates is sensitive, so only its KEYS are ever
  # unmarked, and only after sensitive() has guaranteed a mark for nonsensitive()
  # to strip - an empty map carries none. No PEM and no private key is unmarked
  # anywhere in this layer.
  supplied_certificate_keys = nonsensitive(sensitive(sort(keys(var.origin_pull_certificates))))

  # A zone key with no entry is not configured by this layer at all. A key with
  # no matching zone is an operator error, reported by preflight.tf rather than
  # silently dropped here.
  managed_zones = {
    for key, config in var.origin_pulls : key => config
    if contains(keys(var.zones), key)
  }

  zone_hostname_certificate_keys = {
    for key, config in local.managed_zones : key => distinct([
      for entry in config.hostnames : entry.certificate_key if entry.certificate_key != null
    ])
  }

  zone_level_enabled = {
    for key, config in local.managed_zones : key => coalesce(config.enabled, var.default_zone_level_enabled)
  }

  # Null means "use the copy vendored with this layer", which is the normal case.
  # See ca/README.md for how it is refreshed.
  cloudflare_origin_pull_ca = coalesce(
    var.cloudflare_origin_pull_ca_certificate,
    file("${path.module}/ca/cloudflare_origin_pull_ca.pem"),
  )

  # A zone relies on Cloudflare's default client certificate when zone-level
  # Authenticated Origin Pulls is on and it uploaded none of its own. Only then
  # does its origin need Cloudflare's CA - for a zone with a certificate of its
  # own, adding the CA would make the origin accept the default certificate too,
  # which is what the dedicated one was uploaded to stop.
  uses_shared_certificate = {
    for key, config in local.managed_zones : key => local.zone_level_enabled[key] && config.certificate_key == null
  }

  # Module inputs, one entry per zone.
  #
  # A certificate_key that names nothing supplied resolves to null / is dropped
  # here rather than failing as an invalid index; preflight.tf reports it, and
  # the module reports it again against its own inputs.
  origin_pulls = {
    for key, config in local.managed_zones : key => {
      domain_name = var.zones[key].domain_name
      enabled     = local.zone_level_enabled[key]

      # try() covers both "no certificate_key" and "a key naming material that
      # was not supplied" in one expression, without an index error in either
      # case. The second is reported by preflight.tf.
      zone_certificate = try(var.origin_pull_certificates[config.certificate_key], null)

      hostname_certificates = {
        for certificate_key in local.zone_hostname_certificate_keys[key] :
        certificate_key => var.origin_pull_certificates[certificate_key]
        if contains(local.supplied_certificate_keys, certificate_key)
      }

      hostnames = config.hostnames

      origin_pull_ca_certificate = local.uses_shared_certificate[key] ? local.cloudflare_origin_pull_ca : ""
    }
  }

  # Derived assertions, consumed by preflight.tf

  orphaned_origin_pull_keys = sort([
    for key in keys(var.origin_pulls) : key
    if !contains(keys(var.zones), key)
  ])

  # Every certificate_key anywhere in the configuration, carrying where it was
  # written, so a missing one names the entry at fault rather than the key alone.
  certificate_references = concat(
    [
      for key, config in local.managed_zones : {
        where           = "origin_pulls.${key}.certificate_key"
        certificate_key = config.certificate_key
      }
      if config.certificate_key != null
    ],
    flatten([
      for key, config in local.managed_zones : [
        for entry in config.hostnames : {
          where           = "origin_pulls.${key}.hostnames \"${entry.hostname}\".certificate_key"
          certificate_key = entry.certificate_key
        }
        if entry.certificate_key != null
      ]
    ]),
  )

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

  shared_certificate_zones = sort([
    for key, shared in local.uses_shared_certificate :
    "origin_pulls.${key} (${var.zones[key].domain_name})" if shared
  ])
}
