# No private key and no read-back of the sensitive material. What is exported
# is public certificate material, identifiers, status and expiry dates.

output "universal_ssl_enabled" {
  description = "Whether Universal SSL is on, or null where this module does not manage it."
  value       = one(cloudflare_universal_ssl_setting.this[*].enabled)
}

output "total_tls" {
  description = "Total TLS state (enabled, certificate_authority, validity_period), or null where this module does not manage it."
  value = one([
    for total_tls in cloudflare_total_tls.this : {
      enabled               = total_tls.enabled
      certificate_authority = total_tls.certificate_authority
      validity_period       = total_tls.validity_period
    }
  ])
}

output "certificate_packs" {
  description = <<-EOT
    Per certificate pack key: its ID, status, the qualified hosts it covers,
    and the validation records the CA is waiting on.

    `status` is `active` once issued. On a full DNS setup Cloudflare adds the
    TXT validation records itself. On a partial (CNAME) setup somebody has to
    publish `validation_records` (or `dcv_delegation_records`) at the
    authoritative DNS provider, or the pack never leaves pending_validation.
    `expires_on` is informational: Cloudflare renews packs itself.
  EOT
  value = {
    for key, pack in cloudflare_certificate_pack.this : key => {
      id                     = pack.id
      status                 = pack.status
      hosts                  = sort(tolist(pack.hosts))
      certificate_authority  = pack.certificate_authority
      validation_method      = pack.validation_method
      validity_days          = pack.validity_days
      validation_records     = pack.validation_records
      dcv_delegation_records = pack.dcv_delegation_records
      validation_errors      = pack.validation_errors
      expires_on             = try(sort([for certificate in pack.certificates : certificate.expires_on])[0], null)
    }
  }
}

output "custom_certificates" {
  description = "Per custom certificate key: its ID, status, the hosts Cloudflare read from the certificate, issuer, type and expiry. `expires_on` is the date to replace the material before: Cloudflare does not renew an uploaded certificate, and an expired one fails every handshake it serves."
  value = {
    for key, cert in cloudflare_custom_ssl.this : key => {
      id            = cert.id
      status        = cert.status
      hosts         = cert.hosts
      issuer        = cert.issuer
      type          = cert.type
      bundle_method = cert.bundle_method
      expires_on    = cert.expires_on
    }
  }
}

output "origin_ca_certificates" {
  description = <<-EOT
    Per Origin CA key: its ID, hostnames, expiry and the issued certificate as
    PEM. The certificate is public material and is what gets installed on the
    origin, next to the private key that never left it.

    Cloudflare sends no expiry notification for Origin CA certificates.
    `expires_on` is the date to have rotated by: add a new entry, install it,
    then remove the old one.
  EOT
  value = {
    for key, cert in cloudflare_origin_ca_certificate.this : key => {
      id           = cert.id
      hostnames    = cert.hostnames
      request_type = cert.request_type
      expires_on   = cert.expires_on
      certificate  = cert.certificate
    }
  }
}
