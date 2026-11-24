# Account: account_a - edge and origin certificates. Consumed by the certificates layer only.
#
#   terraform -chdir=layers/certificates plan \
#     -var-file=../../accounts/account_a/account.tfvars \
#     -var-file=../../accounts/account_a/zones.tfvars \
#     -var-file=../../accounts/account_a/certificates.tfvars
#
# A zone with no entry, and any part of an entry left out, is left exactly as
# Cloudflare has it. Universal SSL keeps working on every zone not listed here.
#
# Certificate packs and Total TLS need Advanced Certificate Manager on the zone,
# which is a paid add-on bought outside Terraform. Without it the apply fails.
#
# NO CERTIFICATE OR PRIVATE KEY GOES IN THIS FILE. Custom certificate material
# is set as the TF_VAR_CUSTOM_CERTIFICATES secret on the <account>-plan
# environment and referenced here by key only. An Origin CA CSR may be committed
# here, because a CSR is public; its private key stays on the origin.

certificates = {
  primary = {
    # One advanced certificate for the apex (added automatically), www and the
    # first-level wildcard. Google Trust Services, 90 days, TXT validation -
    # the defaults in layers/certificates/defaults.auto.tfvars.
    certificate_packs = {
      edge = {
        hosts = ["www", "*"]
      }
    }

    # A certificate for every proxied hostname the pack above does not cover,
    # such as a second-level name like api.eu.example.com. Terraform cannot
    # delete this setting: turn it off with enabled = false.
    total_tls = {
      enabled = true
    }
  }
}

# ---------------------------------------------------------------------------
# Disabling Universal SSL
# ---------------------------------------------------------------------------
# Only once every hostname has another active certificate. The plan refuses
# universal_ssl = false on a zone with no certificate pack or custom
# certificate here, but it cannot tell whether those cover every hostname.
# Apply the pack first, confirm it is active in the certificate_packs output,
# then add this in a separate pull request.
#
#     universal_ssl = false

# ---------------------------------------------------------------------------
# Origin CA certificate
# ---------------------------------------------------------------------------
# Commented out because it needs a real CSR, and a placeholder fails at apply.
#
# Generate the key and CSR on the origin itself, so the private key never
# leaves it:
#
#   openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
#     -keyout origin.key -out origin.csr -subj "/CN=example.com"
#
# Paste only origin.csr below. The plan fails if a PRIVATE KEY block is pasted
# by mistake. After apply, the certificate is in the origin_ca_certificates
# output. It is trusted by the Cloudflare edge only, so the hostnames must be
# proxied and the zone's SSL mode full or strict.
#
# To rotate: add a second entry (origin_2027), apply, install it on the origin,
# then delete the first entry, which revokes it. Editing an issued entry in
# place fails the plan, because it would revoke the certificate in use.
#
#     origin_ca_certificates = {
#       origin = {
#         hostnames    = ["@", "*"]
#         request_type = "origin-ecc"
#         csr          = <<-EOT
#           -----BEGIN CERTIFICATE REQUEST-----
#           <contents of origin.csr>
#           -----END CERTIFICATE REQUEST-----
#         EOT
#       }
#     }

# ---------------------------------------------------------------------------
# Custom certificate
# ---------------------------------------------------------------------------
# Business and Enterprise zones only.
#
#   jq -n --rawfile cert www.crt --rawfile key www.key \
#     '{www_2027: {certificate: $cert, private_key: $key}}' \
#     | gh secret set TF_VAR_CUSTOM_CERTIFICATES --repo <owner/repo> --env account_a-plan
#
# www.crt is the leaf followed by its intermediates. Cloudflare does not renew
# it; replace the material in the secret before expires_on.
#
#     custom_certificates = {
#       www = {
#         certificate_key = "www_2027"
#       }
#     }
