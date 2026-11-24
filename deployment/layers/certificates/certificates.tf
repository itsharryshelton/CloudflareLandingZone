# Edge and origin TLS certificates: Universal SSL, Total TLS, advanced
# certificate packs, uploaded custom certificates and Origin CA certificates.
#
# Its own layer rather than part of zones, for the same two reasons as
# origin_pulls. Its state can hold custom certificate private keys, which
# should not sit in the state most people plan against. And its token needs
# SSL and Certificates:Edit without Zone:Edit or DNS:Edit: choosing the
# certificate a hostname serves and repointing that hostname together are
# enough to impersonate it.
#
# Not merged into origin_pulls, although both use the same grant: one decides
# what visitors are shown, the other what the origin is shown, and they are
# reviewed by different people.
#
# One module instance per zone.
#
# Downstream deployments pin an immutable tag instead of the local path:
#   source = "git::https://github.com/yourorg/CloudflareLandingZone//modules/certificates?ref=v1.0.0"
module "certificates" {
  source = "../../../modules/certificates"

  for_each = local.certificates

  zone_id   = data.cloudflare_zone.this[each.key].zone_id
  zone_name = each.value.domain_name

  universal_ssl_enabled       = each.value.universal_ssl
  total_tls                   = each.value.total_tls
  certificate_packs           = each.value.certificate_packs
  custom_certificates         = each.value.custom_certificates
  custom_certificate_material = each.value.custom_certificate_material
  origin_ca_certificates      = each.value.origin_ca_certificates
}
