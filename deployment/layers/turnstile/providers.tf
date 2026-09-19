# The token is read from CLOUDFLARE_API_TOKEN. Never put it in a .tf or .tfvars.
#
# Minimum token scope for this layer, at account level:
#   Turnstile:Edit   (the API refers to the same grant as Turnstile Sites Write)
#
# That grant reaches widgets and nothing else, which makes this one of the few
# layers whose token is genuinely narrow: it cannot read a zone, touch a rule or
# see Zero Trust. Note what it CAN do - reading a widget returns its secret key,
# so a read-only Turnstile token is not a low-value credential.
provider "cloudflare" {}
