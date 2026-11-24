# TLS certificates for one zone: what the edge presents to visitors (Universal
# SSL, Total TLS, advanced certificate packs, uploaded custom certificates) and
# what the origin presents to the edge (Origin CA certificates).
#
# All of it is behind one permission group, SSL and Certificates:Edit, which is
# why it is one module rather than four. Every part is optional: an empty input
# creates nothing and leaves that part of the zone as Cloudflare has it.
#
# Normalisation and reference checks live in locals.tf. The preconditions below
# compare more than one input, or a sensitive one, so they cannot be variable
# validations.

# Declared either way round once set. Writing enabled = true is not a no-op: it
# is what makes a dashboard switch-off show as drift.
resource "cloudflare_universal_ssl_setting" "this" {
  count = var.universal_ssl_enabled == null ? 0 : 1

  zone_id = var.zone_id
  enabled = var.universal_ssl_enabled

  lifecycle {
    precondition {
      condition     = var.universal_ssl_enabled != false || local.has_replacement_edge_certificate
      error_message = "universal_ssl_enabled = false on ${var.zone_name}, but this zone orders no certificate pack and uploads no custom certificate. Disabling Universal SSL removes its certificate from the edge, and every hostname without another valid certificate then fails new TLS handshakes. Add a certificate pack covering the zone's hostnames, apply it, wait for it to show active in the certificate_packs output, and only then disable Universal SSL."
    }
  }
}

resource "cloudflare_total_tls" "this" {
  count = var.total_tls == null ? 0 : 1

  zone_id               = var.zone_id
  enabled               = var.total_tls.enabled
  certificate_authority = var.total_tls.certificate_authority
}

# Ordered before the old pack is deleted. A pack cannot be changed, so every
# edit replaces it, and destroying first would leave its hostnames on whatever
# else covers them, or on nothing, until the new pack validates.
resource "cloudflare_certificate_pack" "this" {
  for_each = local.certificate_packs

  zone_id               = var.zone_id
  type                  = "advanced"
  hosts                 = each.value.hosts
  certificate_authority = each.value.certificate_authority
  validation_method     = each.value.validation_method
  validity_days         = each.value.validity_days
  cloudflare_branding   = each.value.cloudflare_branding

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = length(local.foreign_pack_hosts) == 0
      error_message = "These certificate pack hosts do not belong to ${var.zone_name}: ${join("; ", local.foreign_pack_hosts)}. A pack is ordered on one zone and can only cover that zone's names. Use a relative label, \"*\", \"@\", or a name ending in .${var.zone_name}."
    }

    precondition {
      condition     = length(local.oversized_packs) == 0
      error_message = "These certificate packs list more than 50 names, the apex included: ${join("; ", local.oversized_packs)}. Split them into several packs."
    }

    precondition {
      condition     = length(local.unsupported_validity) == 0
      error_message = "These certificate packs ask for a validity period their CA does not issue: ${join("; ", local.unsupported_validity)}. Let's Encrypt issues 90 days only, Google Trust Services 14, 30 or 90, and SSL.com 14, 30 or 90, or 365 on Enterprise."
    }

    precondition {
      condition     = length(local.wildcard_without_txt) == 0
      error_message = "These certificate packs cover a wildcard but do not validate by TXT record: ${join("; ", local.wildcard_without_txt)}. A CA validates a wildcard through DNS only. Set validation_method = \"txt\"."
    }

    precondition {
      condition     = length(local.long_hosts_without_branding) == 0
      error_message = "These names are longer than the 64 characters a certificate's common name allows: ${join("; ", local.long_hosts_without_branding)}. Set cloudflare_branding = true on the pack so the common name is a short Cloudflare name and these become SANs."
    }
  }
}

# New material replaces the certificate rather than updating it, so the
# replacement is uploaded before the old one is deleted. The other order leaves
# the hostnames on Universal SSL, or on nothing, for the length of the apply.
# That needs one free slot in the zone's quota; without one the upload fails
# and the old certificate stays, which is the safe way to fail.
#
# Keys come from the non-sensitive settings map; the material is looked up with
# try() so a missing entry reaches the precondition below instead of an index
# error.
resource "cloudflare_custom_ssl" "this" {
  for_each = var.custom_certificates

  zone_id       = var.zone_id
  certificate   = try(var.custom_certificate_material[each.key].certificate, "")
  private_key   = try(var.custom_certificate_material[each.key].private_key, "")
  bundle_method = each.value.bundle_method
  type          = each.value.type

  geo_restrictions = each.value.geo_restriction == null ? null : {
    label = each.value.geo_restriction
  }

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = length(local.missing_material) == 0
      error_message = "custom_certificates entries have no material in custom_certificate_material: ${join(", ", local.missing_material)}. Material supplied for: ${join(", ", local.material_keys)}."
    }

    # A private key nothing uses is one nobody rotates and nobody misses when it
    # leaks, and it is in state either way.
    precondition {
      condition     = length(local.unreferenced_material) == 0
      error_message = "custom_certificate_material holds keys with no custom_certificates entry: ${join(", ", local.unreferenced_material)}. Remove the material, or add the entry it was meant for."
    }

    precondition {
      condition     = length(local.malformed_material) == 0
      error_message = "These custom certificates do not look like PEM: ${join(", ", local.malformed_material)}. The certificate must begin with -----BEGIN CERTIFICATE----- and the key with -----BEGIN PRIVATE KEY----- (or the RSA/EC variant), headers, footers and line breaks intact. A value pasted through a JSON environment variable usually loses them."
    }
  }
}

# Deleting an Origin CA certificate revokes it, and the origin keeps serving it
# until somebody changes the origin. So an issued certificate is treated as
# immutable: changes to it are ignored, and the postcondition turns "ignored"
# into a failed plan. Without that, a changed CSR would either be replaced
# (revoking the certificate in use) or silently not applied.
resource "cloudflare_origin_ca_certificate" "this" {
  for_each = local.origin_ca_certificates

  csr                = each.value.csr
  hostnames          = each.value.hostnames
  request_type       = each.value.request_type
  requested_validity = each.value.requested_validity

  lifecycle {
    # requested_validity is ignored and not checked below: the API may report it
    # differently from what was asked, which would fail every plan.
    ignore_changes = [csr, hostnames, request_type, requested_validity]

    precondition {
      condition     = length(local.foreign_origin_ca_hosts) == 0
      error_message = "These Origin CA hostnames do not belong to ${var.zone_name}: ${join("; ", local.foreign_origin_ca_hosts)}. Each certificate is managed with one zone; issue another zone's from that zone's entry."
    }

    precondition {
      condition     = length(local.oversized_origin_ca) == 0
      error_message = "These Origin CA certificates have no hostnames, or more than the 200 Cloudflare allows: ${join("; ", local.oversized_origin_ca)}."
    }

    postcondition {
      condition = (
        replace(self.csr, "/\\s+/", "") == local.origin_ca_csr_fingerprints[each.key]
        && sort(distinct([for host in self.hostnames : lower(host)])) == each.value.hostnames
        && self.request_type == each.value.request_type
      )
      error_message = "origin_ca_certificates.${each.key} on ${var.zone_name} has changed its csr, hostnames or request_type since it was issued. An Origin CA certificate cannot be changed, and replacing it would revoke the certificate the origin is serving. To rotate, add a new entry under a new key, apply, install the new certificate on the origin, then remove this entry. To undo an accidental edit, restore the previous values."
    }
  }
}
