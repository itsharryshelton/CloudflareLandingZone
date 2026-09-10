# The token is read from CLOUDFLARE_API_TOKEN. Never put it in a .tf or .tfvars.
#
# Minimum token scope for this layer:
#   Account  Cloudflare Tunnel:Edit - tunnels, their remote configuration, private
#                                     network routes and virtual networks
#
# Public hostnames need two more, and only if an ingress rule names a zone_key:
#   Zone     Zone:Read              - so data.cloudflare_zone can resolve a key to its ID
#   Zone     DNS:Edit               - to write the proxied CNAME that points the
#                                     hostname at the tunnel
#
# It deliberately carries nothing from the Access or Gateway permission groups.
# This token decides what is reachable; it cannot decide who may reach it.
#
# What it CAN do is worth stating plainly. It can publish any internal service on
# a public hostname, route any private range to any connector, and - because
# the connector token endpoint accepts the same permission - fetch the token that
# runs any tunnel on the account. Give it the same reviewer list as zerotrust.
provider "cloudflare" {}
