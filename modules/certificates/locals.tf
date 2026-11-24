locals {
  # Hostname qualification
  #
  # Cloudflare stores every name fully-qualified, so a relative label would read
  # back as an FQDN and show drift on every plan. "@" is the apex, "*" the
  # first-level wildcard, and a single label is qualified with the zone. A name
  # that already holds a dot is left as written, so one from another zone is
  # reported below rather than being turned into "api.other.com.example.com".
  pack_host_inputs = {
    for key, pack in var.certificate_packs : key => [
      for host in pack.hosts : trimsuffix(lower(trimspace(host)), ".")
    ]
  }

  pack_hosts_qualified = {
    for key, hosts in local.pack_host_inputs : key => [
      for host in hosts : (
        contains(["@", var.zone_name], host) ? var.zone_name
        : host == "*" ? "*.${var.zone_name}"
        : endswith(host, ".${var.zone_name}") ? host
        : length(split(".", host)) == 1 ? "${host}.${var.zone_name}"
        : host
      )
    ]
  }

  # Sorted and de-duplicated, with the apex always present. Cloudflare reads
  # `hosts` back as a set, so order and repeats never cause drift.
  certificate_packs = {
    for key, pack in var.certificate_packs : key => merge(pack, {
      hosts = sort(distinct(concat([var.zone_name], local.pack_hosts_qualified[key])))
    })
  }

  origin_ca_host_inputs = {
    for key, cert in var.origin_ca_certificates : key => [
      for host in cert.hostnames : trimsuffix(lower(trimspace(host)), ".")
    ]
  }

  origin_ca_hosts_qualified = {
    for key, hosts in local.origin_ca_host_inputs : key => [
      for host in hosts : (
        contains(["@", var.zone_name], host) ? var.zone_name
        : host == "*" ? "*.${var.zone_name}"
        : endswith(host, ".${var.zone_name}") ? host
        : length(split(".", host)) == 1 ? "${host}.${var.zone_name}"
        : host
      )
    ]
  }

  origin_ca_certificates = {
    for key, cert in var.origin_ca_certificates : key => merge(cert, {
      hostnames = sort(distinct(local.origin_ca_hosts_qualified[key]))
    })
  }

  # The CSR compared with all whitespace removed. The API may return it with
  # different line endings or wrapping from what was sent, and a difference in
  # whitespace alone must not fail the immutability check in main.tf.
  origin_ca_csr_fingerprints = {
    for key, cert in var.origin_ca_certificates : key => replace(cert.csr, "/\\s+/", "")
  }

  # Custom certificate material
  #
  # var.custom_certificate_material is sensitive, so only its KEYS and derived
  # booleans are ever unmarked - never a certificate and never a private key.
  # sensitive() first because nonsensitive() refuses a value with no mark, which
  # is what an empty map produces.
  material_keys = nonsensitive(sensitive(sort(keys(var.custom_certificate_material))))

  malformed_material = nonsensitive(sensitive(sort([
    for key, material in var.custom_certificate_material : key
    if !can(regex("-----BEGIN CERTIFICATE-----", material.certificate))
    || !can(regex("-----BEGIN [A-Z ]*PRIVATE KEY-----", material.private_key))
  ])))

  # Derived assertions, consumed by the preconditions in main.tf

  foreign_pack_hosts = sort(flatten([
    for key, hosts in local.pack_hosts_qualified : [
      for idx, host in hosts : "certificate_packs.${key}.hosts[${idx}] -> \"${var.certificate_packs[key].hosts[idx]}\""
      if host != var.zone_name && !endswith(host, ".${var.zone_name}")
    ]
  ]))

  oversized_packs = sort([
    for key, pack in local.certificate_packs : "certificate_packs.${key} (${length(pack.hosts)} names)"
    if length(pack.hosts) > 50
  ])

  # Validity periods each CA issues, from Cloudflare's certificate authority
  # reference. 365 from SSL.com is Enterprise only, which this module cannot
  # see; Cloudflare rejects it at apply on a lower plan.
  ca_validity_days = {
    google       = [14, 30, 90]
    lets_encrypt = [90]
    ssl_com      = [14, 30, 90, 365]
  }

  unsupported_validity = sort([
    for key, pack in var.certificate_packs :
    "certificate_packs.${key} (${pack.certificate_authority}, ${pack.validity_days} days)"
    if !contains(lookup(local.ca_validity_days, pack.certificate_authority, []), pack.validity_days)
  ])

  # Domain validation for a wildcard has to be by DNS: a CA cannot prove
  # control of every name under it from one HTTP file or one mailbox.
  wildcard_without_txt = sort([
    for key, pack in local.certificate_packs : "certificate_packs.${key} (validation_method = \"${pack.validation_method}\")"
    if pack.validation_method != "txt" && anytrue([for host in pack.hosts : startswith(host, "*.")])
  ])

  # A certificate's common name is at most 64 characters. Branding moves the
  # common name to a short Cloudflare name, so longer hosts fit as SANs.
  long_hosts_without_branding = sort(flatten([
    for key, pack in local.certificate_packs : [
      for host in pack.hosts : "certificate_packs.${key} -> \"${host}\" (${length(host)} characters)"
      if length(host) > 64
    ]
    if !pack.cloudflare_branding
  ]))

  foreign_origin_ca_hosts = sort(flatten([
    for key, hosts in local.origin_ca_hosts_qualified : [
      for idx, host in hosts : "origin_ca_certificates.${key}.hostnames[${idx}] -> \"${var.origin_ca_certificates[key].hostnames[idx]}\""
      if host != var.zone_name && !endswith(host, ".${var.zone_name}")
    ]
  ]))

  oversized_origin_ca = sort([
    for key, cert in local.origin_ca_certificates : "origin_ca_certificates.${key} (${length(cert.hostnames)} names)"
    if length(cert.hostnames) > 200 || length(cert.hostnames) == 0
  ])

  missing_material = sort([
    for key in keys(var.custom_certificates) : key
    if !contains(local.material_keys, key)
  ])

  unreferenced_material = sort([
    for key in local.material_keys : key
    if !contains(keys(var.custom_certificates), key)
  ])

  # Something other than Universal SSL is configured here to serve the zone.
  # It does not prove every hostname is covered; see var.universal_ssl_enabled.
  has_replacement_edge_certificate = length(var.certificate_packs) > 0 || length(var.custom_certificates) > 0
}
