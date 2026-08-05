#The token is read from CLOUDFLARE_API_TOKEN
#
# Minimum token scope for this layer: Account Load Balancers:Edit (monitors and
# pools are account-scoped), Zone Load Balancers:Edit, and Zone:Read so
# data.cloudflare_zone can resolve a domain to its ID. It does NOT need Zone:Edit.
provider "cloudflare" {}
