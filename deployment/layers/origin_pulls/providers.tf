# The token is read from CLOUDFLARE_API_TOKEN. Never put it in a .tf or .tfvars.
#
# Minimum token scope for this layer, at zone scope:
#   SSL and Certificates:Edit   the zone-level setting, the client certificates
#                               and the per-hostname associations all sit behind
#                               this one grant
#   Zone:Read                   so data.cloudflare_zone can resolve a zone key
#                               to its ID
#
# Notably NOT Zone:Edit and not DNS:Edit. This token can change what the edge
# presents to an origin; it cannot change where a hostname points, which is the
# separation worth having - an attacker holding both could repoint a hostname at
# an origin of their own and have the edge authenticate to it.
#
# The certificates themselves do not come through this token. They arrive as
# TF_VAR_origin_pull_certificates. See variables.tf.
provider "cloudflare" {}
