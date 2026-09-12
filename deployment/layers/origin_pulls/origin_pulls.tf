# Authenticated Origin Pulls: the client certificate the Cloudflare edge
# presents to the origin, zone-wide and per hostname.
#
# Its own layer rather than part of zones. Two reasons, and the second is the
# one that settles it. Its state holds private keys, and putting them in the
# state that also owns every zone would make the most sensitive state in the
# repository the one most people need to plan against. And its token needs
# SSL and Certificates:Edit but must not hold Zone:Edit or DNS:Edit - an
# identity the origin trusts, plus the ability to repoint a hostname, is a
# materially bigger prize than either on its own.
#
# One module instance per zone.
#
# Downstream deployments pin an immutable tag instead of the local path:
#   source = "git::https://github.com/yourorg/CloudflareLandingZone//modules/authenticated_origin_pulls?ref=v1.0.0"
module "origin_pulls" {
  source = "../../../modules/authenticated_origin_pulls"

  for_each = local.origin_pulls

  zone_id   = data.cloudflare_zone.this[each.key].zone_id
  zone_name = each.value.domain_name

  enabled               = each.value.enabled
  zone_certificate      = each.value.zone_certificate
  hostname_certificates = each.value.hostname_certificates
  hostnames             = each.value.hostnames

  origin_pull_ca_certificate = each.value.origin_pull_ca_certificate
}
