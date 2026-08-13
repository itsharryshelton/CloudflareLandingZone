# The token is read from CLOUDFLARE_API_TOKEN
#
# Minimum token scope for this layer, all at account level:
#   Zero Trust:Edit          (the API refers to the same grant as Zero Trust Write)
provider "cloudflare" {}
