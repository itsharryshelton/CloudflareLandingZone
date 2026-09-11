# The token is read from CLOUDFLARE_API_TOKEN. Never put it in a .tf or .tfvars.
#
# Minimum token scope for this layer, at account level:
#   Zero Trust:Edit   (the API refers to the same grant as Zero Trust Write)
#
# Both device posture rules and service provider integrations sit behind that
# one grant, and it is the same grant the gateway layer's token holds - Cloudflare
# has no narrower permission group for posture. The separation this layer buys
# is of state and of review, not of API scope: see .github/workflows/README.md.
#
# The third-party credentials an integration connects with do not come through
# this token. They arrive as TF_VAR_device_posture_integration_secrets. See
# variables.tf.
provider "cloudflare" {}
