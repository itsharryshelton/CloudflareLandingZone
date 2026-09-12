# Cross-variable checks

resource "terraform_data" "preflight" {
  input = {
    zones                 = length(var.zones)
    configured_zones      = length(local.managed_zones)
    zone_level_enabled    = length([for enabled in local.zone_level_enabled : enabled if enabled])
    hostname_associations = sum(concat([0], [for config in local.managed_zones : length(config.hostnames)]))
  }

  lifecycle {
    precondition {
      condition     = length(local.orphaned_origin_pull_keys) == 0
      error_message = "origin_pulls has entries with no matching zone in var.zones: ${join(", ", local.orphaned_origin_pull_keys)}. Valid zone keys: ${join(", ", keys(var.zones))}. Left unchecked, a zone somebody believed was authenticating its origin would not be, and the plan would still go green."
    }

    precondition {
      condition     = length(local.missing_certificates) == 0
      error_message = "These entries name a certificate that was not supplied: ${join("; ", local.missing_certificates)}. Supplied keys: ${join(", ", local.supplied_certificate_keys)}. The certificates arrive from the pipeline as TF_VAR_origin_pull_certificates, from the <account>-plan environment, keyed by the same key - never from a .tfvars file. Use certificate_id instead for one already uploaded to the zone outside Terraform."
    }

    # A private key nobody uses is one nobody rotates and nobody misses when it
    # leaks - and it is in this layer's state whether it is used or not.
    precondition {
      condition     = length(local.orphaned_certificates) == 0
      error_message = "origin_pull_certificates holds certificates nothing refers to: ${join(", ", local.orphaned_certificates)}. Either an entry was removed and its certificate was not, or a certificate_key is misspelled and the hostname it was meant for is about to be configured without one. Remove it from the environment secret, and revoke it if it was ever deployed."
    }

    precondition {
      condition     = var.allow_shared_cloudflare_certificate || length(local.shared_certificate_zones) == 0
      error_message = "allow_shared_cloudflare_certificate is false, and these zones would run Authenticated Origin Pulls on the certificate Cloudflare presents by default: ${join("; ", local.shared_certificate_zones)}. That certificate is presented by the edge for every customer on the platform, so it identifies Cloudflare and not this account. Give each zone a certificate of its own through certificate_key, or set allow_shared_cloudflare_certificate = true in layers/origin_pulls/defaults.auto.tfvars on a pull request that says why."
    }
  }
}

# A `check` rather than a precondition: running on Cloudflare's default
# certificate is a legitimate and common choice, so this must not fail the plan.
# It exists because the difference between the two certificates is invisible in
# the diff - both plans read `enabled = true` - and it is the whole of what the
# origin is being asked to trust.
check "shared_certificate_identifies_cloudflare_not_you" {
  assert {
    condition     = length(local.shared_certificate_zones) == 0
    error_message = "${length(local.shared_certificate_zones)} zone(s) run Authenticated Origin Pulls on the certificate Cloudflare presents by default: ${join("; ", local.shared_certificate_zones)}. An origin that trusts it accepts any request proxied through ANY Cloudflare account, not only this one - it proves traffic came through Cloudflare, not that it came through you. That is still worth having in front of an origin that would otherwise accept anything. Where the origin is relied on to identify the tenant, upload a certificate of your own and set certificate_key."
  }
}
