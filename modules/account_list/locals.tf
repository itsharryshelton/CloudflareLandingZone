locals {
  # null, not [], when unmanaged
  items = var.manage_items ? [
    for item in var.items : {
      ip       = item.ip
      asn      = item.asn
      hostname = item.hostname
      comment  = item.comment
    }
  ] : null

  managed_item_count = var.manage_items ? length(var.items) : 0

  # Which row field a given kind expects.
  expected_field = {
    ip       = "ip"
    asn      = "asn"
    hostname = "hostname"
  }

  mismatched_items = [
    for index, item in var.items : "items[${index}]"
    if(var.kind == "ip" && item.ip == null) ||
    (var.kind == "asn" && item.asn == null) ||
    (var.kind == "hostname" && item.hostname == null)
  ]

  # Cloudflare rejects a list containing the same entry twice, and does it after
  # creating the list - so the list exists, empty, and the apply fails.
  row_keys = [
    for item in var.items :
    item.ip != null ? lower(trimspace(item.ip)) : (
      item.asn != null ? "asn:${item.asn}" : lower(trimspace(item.hostname.url_hostname))
    )
  ]

  duplicate_rows = distinct([
    for key in local.row_keys : key
    if length([for other in local.row_keys : other if other == key]) > 1
  ])
}
