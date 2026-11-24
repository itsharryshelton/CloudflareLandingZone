# The token is read from CLOUDFLARE_API_TOKEN. Never put it in a .tf or .tfvars.
#
# Minimum token scope for this layer, at zone scope:
#   SSL and Certificates:Edit   Universal SSL, Total TLS, certificate packs,
#                               custom certificates and Origin CA certificates
#                               all sit behind this one grant
#   Zone:Read                   so data.cloudflare_zone can resolve a zone key
#                               to its ID, plan and custom certificate quota
#
# Notably NOT Zone:Edit and not DNS:Edit, for the same reason as origin_pulls:
# whoever can both choose the certificate a hostname serves and repoint the
# hostname can impersonate it end to end.
#
# It is the same grant the origin_pulls token holds. Cloudflare has no narrower
# permission group, so the separate token buys a separate environment and
# reviewer list, not a smaller blast radius.
#
# Custom certificate material does not come through this token. It arrives as
# TF_VAR_custom_certificates. See variables.tf.
provider "cloudflare" {}
