# Turns the flat operator-facing rows into the shape the Lists API wants, and
# derives the values main.tf's preconditions assert on.
#
# The API nests every redirect field under a `redirect` object, because a list
# item can equally be an IP, a hostname or an ASN depending on the list's kind.
# Operators should not have to type that nesting for a list whose kind is already
# "redirect".

locals {
  items = var.manage_items ? [
    for item in var.items : {
      comment = item.comment
      redirect = {
        source_url = item.source_url
        target_url = item.target_url

        status_code           = item.status_code
        preserve_query_string = item.preserve_query_string
        include_subdomains    = item.include_subdomains
        subpath_matching      = item.subpath_matching
        preserve_path_suffix  = item.preserve_path_suffix
      }
    }
  ] : null

  # Guardrail inputs
  managed_item_count = var.manage_items ? length(var.items) : 0

  # Compared case-insensitively and scheme-free, which is how Cloudflare matches.
  # Two rows differing only in case are one row to the API, and the second is
  # rejected rather than merged.
  normalised_sources = [for item in var.items : lower(trimspace(item.source_url))]

  duplicate_sources = distinct([
    for source in local.normalised_sources : source
    if length([for other in local.normalised_sources : other if other == source]) > 1
  ])
}
