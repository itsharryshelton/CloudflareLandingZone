# Normalisation and per-type entry checks.
#
# Entries are checked against the list type here rather than in variables.tf,
# because the rule for an entry depends on another variable (type), and every
# cross-field rule in a module is asserted from main.tf.

locals {
  # Hostnames and email addresses are case-insensitive, and Cloudflare is free
  # to store either case. Lower-casing before the write means the value in state
  # is the value sent, whatever Cloudflare does with it.
  case_insensitive = contains(["DOMAIN", "EMAIL"], var.type)

  normalised = [
    for item in var.items : {
      value       = local.case_insensitive ? lower(item.value) : item.value
      description = item.description
    }
  ]

  # A bare address is checked as a /32 or /128 so one function covers both.
  ip_as_cidr = [
    for item in var.items : (
      strcontains(item.value, "/") ? item.value : (strcontains(item.value, ":") ? "${item.value}/128" : "${item.value}/32")
    )
  ]

  # The address Terraform's own CIDR functions produce is the canonical one: the
  # network boundary, IPv6 compressed and lower case. That is the form an IP
  # list stores, so anything else is a value that never matches state.
  ip_canonical = [
    for index, item in var.items : (
      !can(cidrhost(local.ip_as_cidr[index], 0)) ? "" :
      strcontains(item.value, "/") ? cidrsubnet(item.value, 0, 0) : cidrhost(local.ip_as_cidr[index], 0)
    )
  ]

  invalid_ip_items = var.type != "IP" ? [] : [
    for index, item in var.items : "\"${item.value}\""
    if !can(cidrhost(local.ip_as_cidr[index], 0))
  ]

  non_canonical_ip_items = var.type != "IP" ? [] : [
    for index, item in var.items : "\"${item.value}\" (write \"${local.ip_canonical[index]}\")"
    if local.ip_canonical[index] != "" && local.ip_canonical[index] != item.value
  ]

  # Permissive on purpose about the characters in a label: Cloudflare accepts
  # non-Latin hostnames in a list, and recommends a list as the way to match
  # one. What is refused is the shape of something that is not a hostname - a
  # scheme, a path, a port, an email address, a wildcard.
  invalid_domain_items = var.type != "DOMAIN" ? [] : [
    for item in local.normalised : "\"${item.value}\""
    if !can(regex("^[^\\s/:@*\"]+$", item.value)) || !strcontains(item.value, ".") || startswith(item.value, ".") || endswith(item.value, ".")
  ]

  invalid_email_items = var.type != "EMAIL" ? [] : [
    for item in local.normalised : "\"${item.value}\""
    if !can(regex("^[^@\\s\"]+@[^@\\s\"]+\\.[^@\\s\"]+$", item.value))
  ]

  # Gateway ignores a trailing slash, so "https://example.com" and
  # "https://example.com/" are the same entry to it and Cloudflare rejects the
  # second as a duplicate.
  invalid_url_items = var.type != "URL" ? [] : [
    for item in var.items : "\"${item.value}\""
    if can(regex("\\s", item.value)) || endswith(item.value, "/")
  ]

  invalid_aaguid_items = var.type != "AAGUID" ? [] : [
    for item in var.items : "\"${item.value}\""
    if !can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", item.value))
  ]

  invalid_serial_items = var.type != "SERIAL" ? [] : [
    for item in var.items : "\"${item.value}\""
    if can(regex("\\s", item.value))
  ]

  # Two rows that normalise to the same value are one entry to Cloudflare, which
  # rejects the write - after the list itself has been created.
  duplicate_values = sort(distinct([
    for item in local.normalised : item.value
    if length([for other in local.normalised : other if other.value == item.value]) > 1
  ]))
}
