# No private keys and no whole-certificate read-backs of sensitive inputs. What
# is exported is the material an origin has to be given (certificates, which are
# public by construction - the edge presents them on every handshake) and the
# identifiers and expiry dates an operator needs to plan a rotation.

output "zone_level_enabled" {
  description = "Whether zone-level Authenticated Origin Pulls is on for this zone. True means Cloudflare presents a client certificate on every origin connection in the zone - it does not mean the origin checks one."
  value       = cloudflare_authenticated_origin_pulls_settings.this.enabled
}

output "zone_certificate" {
  description = "Identifier, issuer, serial number, deployment status and expiry of the zone-level client certificate, or null where the zone uses the certificate Cloudflare presents by default. `status` is Cloudflare's own: only `active` is deployed to the edge."
  value = one([
    for certificate in cloudflare_authenticated_origin_pulls_certificate.this : {
      certificate_id = certificate.certificate_id
      issuer         = certificate.issuer
      serial_number  = certificate.serial_number
      signature      = certificate.signature
      status         = certificate.status
      uploaded_on    = certificate.uploaded_on
      expires_on     = certificate.expires_on
    }
  ])
}

output "hostname_certificates" {
  description = "Per-hostname client certificate metadata per logical certificate key. `id` is the value a hostname association's cert_id takes, and `expires_on` is the date to rotate before - Cloudflare does not renew an uploaded certificate."
  value = {
    for key, certificate in cloudflare_authenticated_origin_pulls_hostname_certificate.this : key => {
      id            = certificate.id
      issuer        = certificate.issuer
      serial_number = certificate.serial_number
      signature     = certificate.signature
      status        = certificate.status
      uploaded_on   = certificate.uploaded_on
      expires_on    = certificate.expires_on
    }
  }
}

output "hostname_associations" {
  description = "Fully-qualified hostname => the certificate it is bound to and whether the edge is presenting it. A hostname listed with enabled = false keeps its association but is served as though only the zone-level setting applied."
  value = {
    for key, entry in local.hostnames : key => {
      enabled = entry.enabled
      cert_id = local.hostname_certificate_ids[key]
    }
  }
}

output "origin_trust_bundle" {
  description = <<-EOT
    PEM bundle of every certificate the origin has to trust for this zone's
    Authenticated Origin Pulls to verify: Cloudflare's Origin Pull CA where it
    was supplied, plus every certificate uploaded by this module.

    This is the file the origin's client-certificate trust store takes:
      - NGINX: write it to disk, then `ssl_client_certificate <path>;` with
        `ssl_verify_client on;` in the server block.
      - Azure Application Gateway: upload as a Trusted Client Certificate on the
        SSL profile, and attach that profile to the listener.
    Both verify the chain only. Neither checks WHICH certificate was presented,
    so where the bundle holds more than one, any of them is accepted.

    Empty where the zone uses Cloudflare's default certificate and no CA was
    supplied - there is then nothing here to install, and the origin must trust
    Cloudflare's published Origin Pull CA instead.
  EOT
  value       = join("\n", local.trust_bundle_parts)
}

output "origin_trust_bundle_sources" {
  description = "What went into origin_trust_bundle, in order, as input names. The bundle is a single blob of PEM; this says how many certificates are in it and where each came from, so a reviewer can tell a bundle that lost a certificate from one that never had it."
  value       = local.trust_bundle_sources
}
