# Account-level Gateway configuration - the switches that sit above the policy
# set, not inside it.
#
# This is a singleton: Cloudflare stores one configuration object per account at
# /accounts/<id>/gateway/configuration, so there is one resource here and no
# for_each. It already exists on every Zero Trust account, which means the first
# apply against an established account MUST import it - see the calling layer's
# imports.tf. Without the import the provider writes the object from this
# configuration alone, and anything set in the dashboard and not represented
# here is at risk of being dropped.
#
# The single most consequential field is tls_decrypt. With it off, an HTTP
# policy still exists and still shows as active in the dashboard, but Gateway
# only ever sees the TLS handshake for an HTTPS request - so a rule matching a
# path, a method, a file type or a DLP profile never fires. Practically every
# HTTP policy is inert until this is on.
#
# Keyed by account ID rather than counted so the instance address is stable and
# nameable - `this["<account_id>"]` is what the caller's import block adopts, and
# it does not shift if the resource is ever made conditional on something else.
resource "cloudflare_zero_trust_gateway_settings" "this" {
  for_each = var.settings == null ? toset([]) : toset([var.account_id])

  account_id = each.key

  # local.effective_settings, not var.settings: it carries the certificate ID
  # from certificate.tf when this module generates the CA, which is also what
  # orders the two writes.
  settings = local.effective_settings

  lifecycle {
    # An HTTP policy that needs the decrypted request is not rejected when
    # inspection is off - it is simply never reached for HTTPS, which is
    # everything. The dashboard shows it as enforced, so nothing surfaces the
    # gap except the traffic that walked past it.
    precondition {
      condition     = local.tls_decrypt_enabled || length(local.http_policies_needing_decryption) == 0
      error_message = "TLS decryption is off but these HTTP policies only match on fields that exist after decryption: ${join("; ", local.http_policies_needing_decryption)}. Gateway sees the handshake and the SNI for an HTTPS request and nothing more, so those rules apply to plaintext HTTP alone while the dashboard shows them as active. Set settings.tls_decrypt.enabled = true, or convert the rules to a network policy matching on sni_domains."
    }

    # Body scanning is the DLP engine reading the request body. There is no body
    # to read on a connection that was never decrypted.
    precondition {
      condition     = local.tls_decrypt_enabled || try(var.settings.body_scanning, null) == null
      error_message = "settings.body_scanning is configured while settings.tls_decrypt.enabled is false. Body scanning inspects the decrypted request body, so with inspection off it scans nothing on HTTPS. Turn TLS decryption on or drop the body_scanning block."
    }

    # fail_closed turns an antivirus outage into an outage for every download.
    # Defensible, and not something to arrive at by accident.
    precondition {
      condition     = var.allow_antivirus_fail_closed || try(var.settings.antivirus.fail_closed, false) == false
      error_message = "settings.antivirus.fail_closed = true blocks any file Cloudflare could not scan, including files too large for the scanner and files it timed out on - so a scanning fault becomes a download outage. Set allow_antivirus_fail_closed = true on a pull request that accepts that trade."
    }
  }
}
