# The token is read from CLOUDFLARE_API_TOKEN. Never put it in a .tf or .tfvars.
#
# Minimum token scope for this layer:
#   DNS:Edit   to manage the records themselves
#   Zone:Read  so data.cloudflare_zone can resolve a zone key to its ID
provider "cloudflare" {}
