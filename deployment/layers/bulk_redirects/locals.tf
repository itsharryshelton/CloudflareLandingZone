# Applies the platform baseline, resolves logical keys to real names, and derives
# the preflight assertions, so that bulk_redirects.tf reads as two plain module
# calls.
#
# Nothing here reads the Cloudflare API. Bulk Redirects are account-scoped and
# carry their own hostnames, so this layer needs no zone ID and no data source -
# which is why it plans offline in CI against every account.

locals {
  zone_domains = [for zone in var.zones : lower(zone.domain_name)]

  # Per-list settings win; anything unset falls back to the platform baseline.
  # Row-level defaults are applied here rather than in the module so that the
  # module stays a plain description of a Cloudflare list, and so that a fleet
  # policy such as "always carry the query string" is stated once.
  bulk_redirect_lists = {
    for key, list in var.bulk_redirect_lists : key => {
      name         = list.name
      description  = list.description
      manage_items = list.manage_items != null ? list.manage_items : var.default_manage_items

      max_managed_items = list.max_managed_items != null ? list.max_managed_items : var.default_max_managed_items

      items = [
        for item in list.items : {
          source_url = trimspace(item.source_url)
          target_url = trimspace(item.target_url)

          status_code           = item.status_code != null ? item.status_code : var.default_status_code
          preserve_query_string = item.preserve_query_string != null ? item.preserve_query_string : var.default_preserve_query_string

          include_subdomains   = item.include_subdomains
          subpath_matching     = item.subpath_matching
          preserve_path_suffix = item.preserve_path_suffix

          comment = item.comment
        }
      ]
    }
  }

  # Order is preserved from the variable: Cloudflare stops at the first rule that
  # redirects, so this list is the evaluation sequence, not a set.
  #
  # `if contains(...)` rather than a bare index: a list_key pointing at nothing
  # must reach the operator as the preflight message naming it, not as
  # "Invalid index" pointing at this file.
  bulk_redirect_rules = [
    for rule in var.bulk_redirect_rules : {
      list_name       = var.bulk_redirect_lists[rule.list_key].name
      description     = rule.description
      enabled         = rule.enabled
      scope_hostnames = rule.scope_hostnames

      scope_domains = [
        for zone_key in rule.scope_zone_keys : var.zones[zone_key].domain_name
        if contains(keys(var.zones), zone_key)
      ]
    }
    if contains(keys(var.bulk_redirect_lists), rule.list_key)
  ]

  # Preflight checks here
  dangling_list_keys = distinct([
    for rule in var.bulk_redirect_rules : "bulk_redirect_rules -> list_key = \"${rule.list_key}\""
    if !contains(keys(var.bulk_redirect_lists), rule.list_key)
  ])

  dangling_scope_zone_keys = distinct(flatten([
    for rule in var.bulk_redirect_rules : [
      for zone_key in rule.scope_zone_keys :
      "bulk_redirect_rules.${rule.list_key}.scope_zone_keys -> \"${zone_key}\""
      if !contains(keys(var.zones), zone_key)
    ]
  ]))

  referenced_list_keys = [for rule in var.bulk_redirect_rules : rule.list_key]

  unreferenced_lists = var.allow_unreferenced_lists ? [] : [
    for key, list in var.bulk_redirect_lists : "bulk_redirect_lists.${key} (\"${list.name}\")"
    if !contains(local.referenced_list_keys, key)
  ]

  # Hostnames this layer would redirect, from both the rows it manages and the
  # scopes it writes. A hostname in no zone in the inventory is a redirect that
  # can never fire, which is invisible from the Cloudflare side.
  managed_source_hostnames = distinct(flatten([
    for key, list in local.bulk_redirect_lists : [
      for item in list.items : lower(split("/", item.source_url)[0])
    ]
  ]))

  scoped_hostnames = distinct(flatten([
    for rule in var.bulk_redirect_rules : [for hostname in rule.scope_hostnames : lower(hostname)]
  ]))

  hostnames_outside_inventory = var.allow_hostnames_outside_zone_inventory ? [] : [
    for hostname in distinct(concat(local.managed_source_hostnames, local.scoped_hostnames)) : hostname
    if !anytrue([
      for domain in local.zone_domains : hostname == domain || endswith(hostname, ".${domain}")
    ])
  ]

  # Rows supplied without the decision to own them. The module rejects this too;
  # naming the list key here is the difference between a message an operator can
  # act on and one that points at a module instance.
  items_without_manage_items = [
    for key, list in local.bulk_redirect_lists : "bulk_redirect_lists.${key} (${length(list.items)} rows)"
    if !list.manage_items && length(list.items) > 0
  ]

  oversized_lists = [
    for key, list in local.bulk_redirect_lists :
    "bulk_redirect_lists.${key} (${length(list.items)} rows, ceiling ${list.max_managed_items})"
    if list.manage_items && length(list.items) > list.max_managed_items
  ]
}
