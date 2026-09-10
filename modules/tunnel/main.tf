# Cloudflare Tunnel (cloudflared)
# tunnel_secret is left unset on purpose
resource "cloudflare_zero_trust_tunnel_cloudflared" "this" {
  for_each = local.tunnels

  account_id = var.account_id
  name       = trimspace(each.value.name)
  config_src = each.value.config_src
}

# Remotely managed tunnels only
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  for_each = local.configured_tunnels

  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this[each.key].id

  config = {
    ingress        = local.tunnel_ingress[each.key]
    origin_request = try(local.origin_requests["tunnel:${each.key}"], null)
  }
}

# An ingress hostname with no DNS record is never reached
resource "cloudflare_dns_record" "this" {
  for_each = local.dns_records

  zone_id = each.value.zone_id
  name    = each.key
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.this[each.value.tunnel_key].id}.cfargotunnel.com"
  ttl     = 1
  proxied = true
  comment = "Cloudflare Tunnel public hostname. Managed by Terraform."
}

# Renaming one destroys and recreates it, and every route scoped to it with it.
resource "cloudflare_zero_trust_tunnel_cloudflared_virtual_network" "this" {
  for_each = local.virtual_networks

  account_id         = var.account_id
  name               = trimspace(each.value.name)
  comment            = each.value.comment
  is_default_network = each.value.is_default_network
}

# The private network routing table: which ranges a WARP client reaches down
# which tunnel, within which virtual network.
resource "cloudflare_zero_trust_tunnel_cloudflared_route" "this" {
  for_each = local.routes

  account_id = var.account_id
  network    = each.value.network
  comment    = each.value.comment

  # try() rather than a bare index, so a name that resolves to nothing reaches
  # the operator as the precondition below rather than as "Invalid index"
  # against this file.
  tunnel_id = try(cloudflare_zero_trust_tunnel_cloudflared.this[each.value.tunnel_key].id, "unresolved")
  virtual_network_id = (
    each.value.virtual_network_key == null
    ? each.value.virtual_network_id
    : try(cloudflare_zero_trust_tunnel_cloudflared_virtual_network.this[each.value.virtual_network_key].id, "unresolved")
  )

  lifecycle {
    precondition {
      condition     = length(local.unknown_route_tunnels) == 0
      error_message = "These routes name a tunnel this module does not declare: ${join("; ", local.unknown_route_tunnels)}. Declared tunnels: ${join(", ", local.tunnel_keys)}."
    }

    precondition {
      condition     = length(local.unknown_route_virtual_networks) == 0
      error_message = "These routes name a virtual network this module does not declare: ${join("; ", local.unknown_route_virtual_networks)}. Declared virtual networks: ${join(", ", local.virtual_network_keys)}. Use virtual_network_id for one managed elsewhere, or neither for the account's default."
    }

    # Cloudflare refuses the second of two identical routes, but only after the
    # first has been created, leaving the apply half done.
    precondition {
      condition     = length(local.duplicate_routes) == 0
      error_message = "These networks are routed more than once within the same virtual network: ${join("; ", local.duplicate_routes)}. A range can reach one tunnel per virtual network. Put the second site's copy of an overlapping range in a virtual network of its own."
    }
  }
}
