# The token is read from CLOUDFLARE_API_TOKEN. Never put it in a .tf or .tfvars.
#
# Minimum token scope for this layer: Zone:Edit, DNS:Edit, Zone Settings:Edit.
provider "cloudflare" {}
