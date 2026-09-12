output "origin_trust_bundles" {
  description = <<-EOT
    Zone key => the PEM bundle that zone's origins have to trust for
    Authenticated Origin Pulls to verify.

    This is the deliverable for whoever configures the origin. Write a zone's
    bundle to a file and point the origin's client-certificate trust store at it:

      terraform -chdir=layers/origin_pulls output -json origin_trust_bundles \
        | jq -r '.primary' >cloudflare-client-ca.pem

      # NGINX / NGINX ingress
      ssl_client_certificate /etc/nginx/cloudflare-client-ca.pem;
      ssl_verify_client on;

      # Azure Application Gateway - upload as a Trusted Client Certificate on an
      # SSL profile, then attach the profile to the listener.

    Certificates only; no private key is in here and none is ever output. A
    certificate is public material - the edge presents it on every handshake.

    Empty for a zone that is configured but has Authenticated Origin Pulls off
    and no certificate uploaded: there is nothing for an origin to trust yet.
  EOT
  value       = { for key, origin_pulls in module.origin_pulls : key => origin_pulls.origin_trust_bundle }
}

output "origin_trust_bundle_sources" {
  description = "Zone key => what went into that zone's bundle, in order. `cloudflare_origin_pull_ca` means the zone is running on the certificate Cloudflare presents by default; anything else is a certificate uploaded from origin_pull_certificates."
  value       = { for key, origin_pulls in module.origin_pulls : key => origin_pulls.origin_trust_bundle_sources }
}

output "zone_level_enabled" {
  description = "Zone key => whether zone-level Authenticated Origin Pulls is on. True means the edge presents a client certificate on every origin connection in the zone; it says nothing about whether the origin checks one."
  value       = { for key, origin_pulls in module.origin_pulls : key => origin_pulls.zone_level_enabled }
}

output "certificates" {
  description = "Zone key => the zone-level certificate's identifier, issuer, status and expiry (null where the zone uses Cloudflare's default), and the same per uploaded per-hostname certificate. `expires_on` is the date to rotate before: Cloudflare does not renew an uploaded certificate, and an expired one fails every origin connection in the zone."
  value = {
    for key, origin_pulls in module.origin_pulls : key => {
      zone_certificate      = origin_pulls.zone_certificate
      hostname_certificates = origin_pulls.hostname_certificates
    }
  }
}

output "hostname_associations" {
  description = "Zone key => fully-qualified hostname => the certificate ID bound to it and whether the edge is presenting it. The quickest check that a per-hostname entry reached this layer and resolved to a certificate."
  value       = { for key, origin_pulls in module.origin_pulls : key => origin_pulls.hostname_associations }
}

output "zone_ids" {
  description = "Zone key => resolved zone ID, for the zones this layer configures. Each one cost an API read at plan time."
  value       = { for key, zone in data.cloudflare_zone.this : key => zone.zone_id }
}
