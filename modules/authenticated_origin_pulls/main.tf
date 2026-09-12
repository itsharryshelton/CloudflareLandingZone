# Authenticated Origin Pulls: mutual TLS between the Cloudflare edge and the
# origin. Cloudflare presents a client certificate on the origin connection, and
# an origin configured to verify it stops accepting traffic that did not come
# through Cloudflare.
#
# Two scopes, and they are separate switches:
#   - zone level, one setting covering every hostname in the zone
#   - per hostname, an association between one hostname and one certificate
# Where both cover a hostname, Cloudflare applies the per-hostname association.
#
# Normalisation and reference resolution live in locals.tf. The preconditions
# below need more than one input, so they cannot be variable validations - and
# on the sensitive certificate variables they could not be written there at all,
# since a validation message may not reference a sensitive value.

# Zone-level Authenticated Origin Pulls, declared either way round. Writing
# enabled = false is not a no-op: it is what makes an operator switching the
# setting on in the dashboard show up as drift on the next plan.
resource "cloudflare_authenticated_origin_pulls_settings" "this" {
  zone_id = var.zone_id
  enabled = var.enabled

  lifecycle {
    precondition {
      condition     = !local.zone_certificate_malformed
      error_message = "zone_certificate does not look like PEM. The certificate must begin with a -----BEGIN CERTIFICATE----- line and the private key with a -----BEGIN PRIVATE KEY----- line (or the RSA/EC variant), each including its header, footer and trailing newline. A value pasted through a JSON-encoded environment variable usually loses them."
    }

    precondition {
      condition     = length(local.malformed_hostname_certificates) == 0
      error_message = "These hostname_certificates entries do not look like PEM: ${join(", ", local.malformed_hostname_certificates)}. Each needs a certificate beginning -----BEGIN CERTIFICATE----- and a private key beginning -----BEGIN PRIVATE KEY----- (or the RSA/EC variant), headers and footers included."
    }

    # An uploaded key that nothing uses is one nobody rotates and nobody misses
    # when it leaks - and it is sitting in this layer's state either way.
    precondition {
      condition     = length(local.unreferenced_certificates) == 0
      error_message = "hostname_certificates holds certificates no hostname refers to: ${join(", ", local.unreferenced_certificates)}. Either a hostname entry was removed and its certificate was not, or a certificate_key is misspelled and the hostname it was meant for is about to be configured without one. Remove the certificate, or point a hostname at it."
    }
  }
}

# A client certificate of the customer's own for zone-level Authenticated Origin
# Pulls. Without one the edge presents Cloudflare's default certificate, which
# every Cloudflare customer's edge also presents.
#
# Replacing the certificate replaces the resource, so it is created before the
# old one is destroyed: the reverse order leaves the zone with no client
# certificate for the length of the apply, and an origin that requires one
# refuses every request in that window.
resource "cloudflare_authenticated_origin_pulls_certificate" "this" {
  count = local.zone_certificate_supplied ? 1 : 0

  zone_id     = var.zone_id
  certificate = var.zone_certificate.certificate
  private_key = var.zone_certificate.private_key

  lifecycle {
    create_before_destroy = true
  }
}

# Certificates for per-hostname Authenticated Origin Pulls. Uploading one does
# not associate it with anything; the association is the resource below.
resource "cloudflare_authenticated_origin_pulls_hostname_certificate" "this" {
  for_each = toset(local.certificate_keys)

  zone_id     = var.zone_id
  certificate = var.hostname_certificates[each.key].certificate
  private_key = var.hostname_certificates[each.key].private_key

  lifecycle {
    create_before_destroy = true
  }
}

# One resource per hostname, each holding a single-entry config list.
#
# The provider's import ID for this resource is "<zone_id>/<hostname>", so its
# read is per hostname however many entries were sent on the write. Modelling a
# zone's hostnames as one resource with a list would therefore reconcile one of
# them and show permanent drift on the rest.
resource "cloudflare_authenticated_origin_pulls" "this" {
  for_each = local.hostnames

  zone_id = var.zone_id

  config = [{
    hostname = each.value.hostname
    enabled  = each.value.enabled
    cert_id  = local.hostname_certificate_ids[each.key]
  }]

  lifecycle {
    precondition {
      condition     = length(local.duplicate_hostnames) == 0
      error_message = "hostnames contains the same hostname more than once: ${join(", ", local.duplicate_hostnames)}. Names are compared fully-qualified, so \"api\" and \"api.${var.zone_name}\" collide - a hostname can hold one certificate association, so each must appear once."
    }

    precondition {
      condition     = length(local.foreign_hostnames) == 0
      error_message = "These hostnames do not belong to ${var.zone_name}: ${join("; ", local.foreign_hostnames)}. A per-hostname association is scoped to one zone, and Cloudflare rejects a hostname outside it. Use a relative label or a name ending in .${var.zone_name}, and configure another zone's hostnames through that zone's own module instance."
    }

    precondition {
      condition     = length(local.unknown_certificate_keys) == 0
      error_message = "certificate_key does not match any entry in var.hostname_certificates: ${join("; ", local.unknown_certificate_keys)}. Declared certificates: ${join(", ", local.certificate_keys)}. Use certificate_id for a certificate already uploaded to the zone outside Terraform."
    }

    precondition {
      condition     = length(local.hostnames_without_certificate) == 0
      error_message = "These hostnames name no certificate: ${join(", ", local.hostnames_without_certificate)}. A per-hostname association binds a hostname to a certificate, so each entry needs certificate_key (one this module uploads) or certificate_id (one already in the zone). To cover a hostname with the zone-level setting instead, drop its entry from hostnames."
    }
  }
}
