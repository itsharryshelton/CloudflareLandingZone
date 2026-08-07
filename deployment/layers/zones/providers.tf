# The token is read from CLOUDFLARE_API_TOKEN. Never put it in a .tf or .tfvars.
#
# Minimum token scope for this layer: Zone:Edit, DNS:Edit, Zone Settings:Edit.
#
# Bot management adds Bot Management:Edit.
#
# manage_zone_subscriptions (or a per-zone manage_subscription) additionally
# needs Billing:Read and Billing:Write, because the layer then changes rate
# plans. Do not add billing rights to the routine pipeline token to enable a
# one-off plan change - use a separate token for that run and take them away
# again afterwards. A token that can rewrite DNS and change what the account is
# billed is a materially bigger prize than one that can only do the first.
provider "cloudflare" {}
