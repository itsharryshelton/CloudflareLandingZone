locals {
  # Re-serialised compactly, with object keys sorted, so a heredoc's indentation
  # or key order in the caller never reads as drift against what Cloudflare
  # stored.
  filter = var.filter == null ? null : jsonencode(jsondecode(var.filter))

  scope = var.zone_id == null ? "account" : "zone"
}
