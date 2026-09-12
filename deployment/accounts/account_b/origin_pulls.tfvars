# Account: account_b - Authenticated Origin Pulls. Consumed by the origin_pulls layer only.
#
# The smallest useful configuration: the edge authenticates to the origin
# zone-wide, on the certificate Cloudflare presents by default. See
# accounts/account_a/origin_pulls.tfvars for the fuller worked example,
# including a dedicated certificate and per-hostname associations.
#
# The origin still has to be told to verify it. Take the PEM out of this layer's
# origin_trust_bundles output after the first apply, install it, and switch the
# origin to require a client certificate last.

origin_pulls = {
  primary = {
    enabled = true
  }
}
