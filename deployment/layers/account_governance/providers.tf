# The token is read from CLOUDFLARE_API_TOKEN. Never put it in a .tf or .tfvars.
#
# Minimum token scope for this layer: Account Settings:Edit.
provider "cloudflare" {}
