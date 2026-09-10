# Cloudflare Tunnel: outbound-only connectors that publish private origins on
# public hostnames, and the private network routes WARP clients reach through
# them.
#
# I kept apart from the zerotrust layer on purpose. Access decides who may reach an
# application; a tunnel decides what is reachable at all. Separate state and a
# separate token mean an Access policy change cannot delete a tunnel, and a
# tunnel change cannot loosen a policy.
#
# One module instance per account. Its ID comes from accounts/<account>/account.tfvars.
#
# Downstream deployments pin an immutable tag instead of the local path:
#   source = "git::https://github.com/yourorg/CloudflareLandingZone//modules/tunnel?ref=v1.0.0"
module "tunnel" {
  source = "../../../modules/tunnel"

  account_id = var.cloudflare_account_id

  tunnels          = local.tunnels
  virtual_networks = local.virtual_networks

  # tunnel_key and virtual_network_key -> the names the module works in, resolved in locals.tf.
  routes = local.routes
}
