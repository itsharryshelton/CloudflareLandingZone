# The token is read from CLOUDFLARE_API_TOKEN
#
# Minimum token scope for this layer, all at account level:
#   Zero Trust:Edit          (the API refers to the same grant as Zero Trust Write)
#
# That one grant covers the policies, the account configuration and the
# inspection CA, and also the Zero Trust lists, DLP profiles and DNS locations
# this layer manages - Cloudflare files all of them under Zero Trust.
provider "cloudflare" {}
