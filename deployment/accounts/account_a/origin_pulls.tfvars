# Account: account_a - Authenticated Origin Pulls. Consumed by the origin_pulls layer only.
#
#   terraform -chdir=layers/origin_pulls plan \
#     -var-file=../../accounts/account_a/account.tfvars \
#     -var-file=../../accounts/account_a/zones.tfvars \
#     -var-file=../../accounts/account_a/origin_pulls.tfvars
#
# Authenticated Origin Pulls is mutual TLS between the Cloudflare edge and the
# origin: the edge presents a client certificate, and an origin configured to
# verify it stops accepting anything that did not come through Cloudflare.
#
# ORDER MATTERS. Applying this changes what Cloudflare SENDS; it does not make
# the origin ask for anything. Apply here first, take the bundle out of the
# layer's origin_trust_bundles output, install it at the origin, and only then
# switch the origin to require a client certificate. The reverse order fails
# every request in between.
#
# Requires the zone's SSL mode to be full or strict, which is the zones layer's
# default. On flexible there is no origin TLS connection to authenticate.
#
# NO CERTIFICATE OR PRIVATE KEY GOES IN THIS FILE. Certificate material is set
# as the TF_VAR_ORIGIN_PULL_CERTIFICATES secret on the <account>-plan
# environment, and referenced here by key only.

origin_pulls = {
  # Zone-wide, on the certificate Cloudflare presents by default.
  primary = {
    enabled = true
  }
  test_domain = {
    enabled = false
  }
}

# ---------------------------------------------------------------------------
# A dedicated certificate, zone-wide and per hostname
# ---------------------------------------------------------------------------
# Commented out because it needs certificate material in the plan environment,
# and a reference to a key that is not there fails the plan by design.
#
# To use it, generate a client certificate (self-signed is normal here - the
# origin trusts the certificate itself, not a public CA), then set the secret:
#
#   gh secret set TF_VAR_ORIGIN_PULL_CERTIFICATES --repo <owner/repo> --env account_a-plan
#
# whose value is one JSON object, with the PEM line breaks kept intact:
#
#   jq -n --rawfile cert api.crt --rawfile key api.key \
#     '{api_origin: {certificate: $cert, private_key: $key}}'
#
# origin_pulls = {
#   primary = {
#     enabled = true
#
#     # Presented on every origin connection in the zone except where a hostname
#     # below overrides it.
#     certificate_key = "edge_client"
#
#     hostnames = [
#       # The one hostname whose origin trusts nothing else. api.example.com's
#       # origin is given only this certificate, so a request proxied through
#       # another Cloudflare account - presenting Cloudflare's default
#       # certificate, or this account's zone-wide one - is refused by it.
#       {
#         hostname        = "api"
#         certificate_key = "api_origin"
#       },
#
#       # Parked, not deleted: the association and its certificate stay, the edge
#       # stops presenting it. This is the reversible way to take a hostname out.
#       {
#         hostname        = "legacy.example.com"
#         enabled         = false
#         certificate_key = "api_origin"
#       },
#
#       # A certificate uploaded to the zone outside Terraform, referenced by ID.
#       # Terraform does not own it and will not rotate or delete it.
#       {
#         hostname       = "partner"
#         certificate_id = "2458ce5a-0c35-4c7f-82c7-8e9487d3ff60"
#       },
#     ]
#   }
# }
