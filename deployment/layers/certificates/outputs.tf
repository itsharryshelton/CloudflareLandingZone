output "certificate_packs" {
  description = "Zone key => certificate pack key => ID, status, hosts, CA, validity and the validation records the CA is waiting on. A pack stuck in pending_validation on a partial (CNAME) setup needs its validation_records published at the authoritative DNS provider."
  value       = { for key, certificates in module.certificates : key => certificates.certificate_packs }
}

output "custom_certificates" {
  description = "Zone key => custom certificate key => ID, status, hosts, issuer, type and expiry. `expires_on` is the date to replace the material before: Cloudflare does not renew an uploaded certificate."
  value       = { for key, certificates in module.certificates : key => certificates.custom_certificates }
}

output "origin_ca_certificates" {
  description = <<-EOT
    Zone key => Origin CA key => ID, hostnames, expiry and the issued
    certificate as PEM - the deliverable for whoever configures the origin.
    Public material; the private key never left the origin.

      terraform -chdir=layers/certificates output -json origin_ca_certificates \
        | jq -r '.primary.origin.certificate' >origin.pem

    Cloudflare sends no expiry notice for these. Rotate before `expires_on`.
  EOT
  value       = { for key, certificates in module.certificates : key => certificates.origin_ca_certificates }
}

output "universal_ssl_enabled" {
  description = "Zone key => whether Universal SSL is on, or null where this layer leaves it unmanaged."
  value       = { for key, certificates in module.certificates : key => certificates.universal_ssl_enabled }
}

output "total_tls" {
  description = "Zone key => Total TLS state, or null where this layer leaves it unmanaged."
  value       = { for key, certificates in module.certificates : key => certificates.total_tls }
}

output "zone_ids" {
  description = "Zone key => resolved zone ID, for the zones this layer configures. Each one cost an API read at plan time."
  value       = { for key, zone in data.cloudflare_zone.this : key => zone.zone_id }
}
