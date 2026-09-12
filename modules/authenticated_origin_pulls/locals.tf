locals {
  # Certificate material
  #
  # var.hostname_certificates and var.zone_certificate are sensitive, and a
  # sensitive value cannot be a for_each key, a count, or part of an error
  # message. Only ever the KEYS and derived booleans are unmarked here - never a
  # PEM and never a private key. sensitive() first because nonsensitive()
  # refuses a value that carries no mark, which is what an empty map produces.
  certificate_keys = nonsensitive(sensitive(sort(keys(var.hostname_certificates))))

  zone_certificate_supplied = nonsensitive(sensitive(var.zone_certificate != null))

  # Shape only. A PEM that parses is not a certificate that works, but a value
  # pasted in without its header lines is the failure worth catching before an
  # apply hands Cloudflare something it will reject.
  malformed_hostname_certificates = nonsensitive(sensitive(sort([
    for key, material in var.hostname_certificates : key
    if !can(regex("-----BEGIN CERTIFICATE-----", material.certificate))
    || !can(regex("-----BEGIN [A-Z ]*PRIVATE KEY-----", material.private_key))
  ])))

  # can() rather than a conditional on zone_certificate_supplied: with no
  # certificate supplied the attribute access itself is the error, and can()
  # swallows it wherever the expression ends up being evaluated.
  zone_certificate_valid = nonsensitive(sensitive(
    can(regex("-----BEGIN CERTIFICATE-----", var.zone_certificate.certificate))
    && can(regex("-----BEGIN [A-Z ]*PRIVATE KEY-----", var.zone_certificate.private_key))
  ))

  zone_certificate_malformed = local.zone_certificate_supplied && !local.zone_certificate_valid

  # Hostnames
  hostname_inputs = [
    for entry in var.hostnames : trimsuffix(lower(trimspace(entry.hostname)), ".")
  ]

  # Cloudflare stores a hostname association fully-qualified, so a relative
  # label read back as an FQDN would show drift on every plan. A single label is
  # qualified with the zone; anything already carrying a dot is left alone, so a
  # name from another zone stays wrong and is reported below rather than being
  # quietly turned into "api.other.example.com".
  #
  # length(split(".", x)) rather than strcontains: this module's floor is
  # Terraform 1.5 and strcontains arrived in 1.6.
  hostname_qualified = [
    for idx, entry in var.hostnames : (
      contains(["@", var.zone_name], local.hostname_inputs[idx])
      ? var.zone_name
      : endswith(local.hostname_inputs[idx], ".${var.zone_name}")
      ? local.hostname_inputs[idx]
      : length(split(".", local.hostname_inputs[idx])) == 1
      ? "${local.hostname_inputs[idx]}.${var.zone_name}"
      : local.hostname_inputs[idx]
    )
  ]

  hostnames_normalised = [
    for idx, entry in var.hostnames : {
      hostname        = local.hostname_qualified[idx]
      enabled         = entry.enabled
      certificate_key = entry.certificate_key
      certificate_id  = entry.certificate_id
    }
  ]

  # Grouped then reduced to [0], so a duplicate is reported by the precondition
  # in main.tf naming the hostname, instead of Terraform's generic
  # "Duplicate object key" pointing into this file.
  hostnames_grouped = {
    for entry in local.hostnames_normalised : entry.hostname => entry...
  }

  hostnames = {
    for key, entries in local.hostnames_grouped : key => entries[0]
  }

  duplicate_hostnames = sort([
    for key, entries in local.hostnames_grouped : key if length(entries) > 1
  ])

  # Reference resolution
  certificate_refs = {
    for key, entry in local.hostnames : key => entry.certificate_key == null ? "" : trimspace(entry.certificate_key)
  }

  # The ID of a certificate uploaded in this same run is unknown at plan, which
  # is why every assertion below is decided from the configuration alone: a
  # condition built on this map would make itself unknown and disappear from
  # the plan the reviewer reads.
  certificate_ids_by_key = {
    for key in local.certificate_keys : key => cloudflare_authenticated_origin_pulls_hostname_certificate.this[key].id
  }

  hostname_certificate_ids = {
    for key, entry in local.hostnames : key => (
      entry.certificate_id != null
      ? entry.certificate_id
      : lookup(local.certificate_ids_by_key, local.certificate_refs[key], null)
    )
  }

  referenced_certificate_keys = distinct([
    for key, ref in local.certificate_refs : ref if ref != ""
  ])

  # Derived assertions, consumed by the preconditions in main.tf

  foreign_hostnames = sort([
    for idx, entry in var.hostnames : "hostnames[${idx}].hostname -> \"${entry.hostname}\""
    if local.hostname_qualified[idx] != var.zone_name
    && !endswith(local.hostname_qualified[idx], ".${var.zone_name}")
  ])

  unknown_certificate_keys = sort([
    for key, ref in local.certificate_refs : "hostnames \"${key}\".certificate_key -> \"${ref}\""
    if ref != "" && !contains(local.certificate_keys, ref)
  ])

  # An association is a hostname bound to a certificate. With no certificate
  # named there is nothing to bind, and nothing for the edge to present on that
  # hostname's origin connections. Checked regardless of `enabled`, because
  # enabled = false is meant to park an existing association, not to declare a
  # half of one.
  hostnames_without_certificate = sort([
    for key, entry in local.hostnames : key
    if entry.certificate_key == null && entry.certificate_id == null
  ])

  unreferenced_certificates = sort([
    for key in local.certificate_keys : key
    if !contains(local.referenced_certificate_keys, key)
  ])

  # What the origin has to trust
  #
  # Built from the inputs rather than from the resources' read-back attributes
  # so that it resolves at PLAN time. The bundle is what gets installed at the
  # origin, and it is needed before the origin is switched to require a client
  # certificate - which is after this applies, but it should not also mean
  # waiting for an apply to find out what to install.
  #
  # Certificates only. A certificate is public material: the edge presents it on
  # every origin handshake. The private keys that pair with them are never read
  # here and never leave this module.

  # try() rather than a conditional, for the same reason as above: with no zone
  # certificate the attribute access is the error, and compact() then drops the
  # empty string it falls back to.
  zone_certificate_pem = nonsensitive(sensitive(try(trimspace(var.zone_certificate.certificate), "")))

  trust_bundle_parts = compact(concat(
    [trimspace(var.origin_pull_ca_certificate), local.zone_certificate_pem],
    [
      for key in local.certificate_keys :
      trimspace(nonsensitive(sensitive(var.hostname_certificates[key].certificate)))
    ],
  ))

  trust_bundle_sources = compact(concat(
    [
      trimspace(var.origin_pull_ca_certificate) == "" ? "" : "cloudflare_origin_pull_ca",
      local.zone_certificate_pem == "" ? "" : "zone_certificate",
    ],
    [for key in local.certificate_keys : "hostname_certificates.${key}"],
  ))
}
