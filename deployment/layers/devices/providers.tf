# The token is read from CLOUDFLARE_API_TOKEN. Never put it in a .tf or .tfvars.
#
# Minimum token scope for this layer, at account level:
#   Zero Trust:Edit   (the API refers to the same grant as Zero Trust Write)
#
# Device settings, device profiles and Local Domain Fallback all sit behind
# that one grant - the same one the gateway and device_posture tokens hold.
# Cloudflare has no narrower permission group for client configuration. The
# separation this layer buys is of state and of review, not of API scope: a
# split tunnel change can take a fleet off the network or out of Gateway's
# sight, so it gets its own plan and its own approval gate. See
# .github/workflows/README.md.
provider "cloudflare" {}
