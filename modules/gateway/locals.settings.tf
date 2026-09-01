# Derived checks for the account-level configuration in settings.tf, and the
# object that is actually written.

locals {
  # The CA from certificate.tf, when this module owns one. Reading the resource
  # here is what makes the configuration write in settings.tf depend on the
  # certificate being generated and activated first, rather than the two going
  # out concurrently and the write losing with a 2211.
  managed_certificate_id = try(cloudflare_zero_trust_gateway_certificate.this[var.account_id].id, null)

  # What is sent to Cloudflare: the caller's settings with certificate.id filled
  # in from the generated CA. A caller naming their own certificate is not
  # overwritten here - that combination is rejected by the precondition in
  # certificate.tf rather than quietly resolved in favour of one of them.
  effective_settings = var.settings == null ? null : merge(
    var.settings,
    local.managed_certificate_id == null ? {} : { certificate = { id = local.managed_certificate_id } }
  )

  # Absent settings means the account configuration is not managed here, and the
  # dashboard value - whatever it is - stands. Treated as "off" for the checks
  # below, because the checks exist to catch a policy set that silently does
  # nothing, and an unmanaged account is exactly where that happens unnoticed.
  tls_decrypt_enabled = try(var.settings.tls_decrypt.enabled, false)

  # Without decryption an HTTP policy only ever sees plaintext HTTP, which on a
  # modern estate is close to nothing. "off" (Do Not Inspect) is excluded: it is
  # evaluated on the handshake, so it works either way and is merely redundant
  # when there is no inspection to turn off.
  http_policies_needing_decryption = sort([
    for key, policy in local.policies : "${key} (action = \"${policy.action}\")"
    if policy.type == "http" && policy.action != "off" && !var.allow_uninspected_http_policies
  ])
}
