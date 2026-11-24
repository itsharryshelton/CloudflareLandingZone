# Cross-variable checks

resource "terraform_data" "preflight" {
  input = {
    zones               = length(var.zones)
    configured_zones    = length(local.managed_zones)
    certificate_packs   = sum(concat([0], [for config in local.managed_zones : length(config.certificate_packs)]))
    custom_certificates = sum(concat([0], [for config in local.managed_zones : length(config.custom_certificates)]))
    origin_ca           = sum(concat([0], [for config in local.managed_zones : length(config.origin_ca_certificates)]))
  }

  lifecycle {
    precondition {
      condition     = length(local.orphaned_certificate_keys) == 0
      error_message = "certificates has entries with no matching zone in var.zones: ${join(", ", local.orphaned_certificate_keys)}. Valid zone keys: ${join(", ", keys(var.zones))}. Left unchecked, a zone somebody believed had a certificate ordered would not, and the plan would still go green."
    }

    precondition {
      condition     = length(local.missing_certificates) == 0
      error_message = "These custom certificates name material that was not supplied: ${join("; ", local.missing_certificates)}. Supplied keys: ${join(", ", local.supplied_certificate_keys)}. The material arrives from the pipeline as TF_VAR_custom_certificates, from the <account>-plan environment, keyed by the same key - never from a .tfvars file."
    }

    # A private key nobody uses is one nobody rotates and nobody misses when it
    # leaks - and it is in this layer's state whether it is used or not.
    precondition {
      condition     = length(local.orphaned_certificates) == 0
      error_message = "custom_certificates holds material nothing refers to: ${join(", ", local.orphaned_certificates)}. Either an entry was removed and its material was not, or a certificate_key is misspelled. Remove it from the environment secret, and revoke it at its CA if it was ever deployed."
    }

    precondition {
      condition     = length(local.over_quota_zones) == 0
      error_message = "These zones list more custom certificates than their plan allows: ${join("; ", local.over_quota_zones)}. The quota is read from Cloudflare: 0 on Free and Pro, 5 (plus 1 legacy) on Business and Enterprise unless more were bought. Cloudflare rejects the upload at apply. Use a certificate pack instead, or remove entries."
    }

    precondition {
      condition     = length(local.total_tls_not_full_setup) == 0
      error_message = "Total TLS is enabled on zones without a full DNS setup: ${join("; ", local.total_tls_not_full_setup)}. Cloudflare only offers Total TLS where it hosts the zone's DNS. Order a certificate pack for the proxied hostnames instead."
    }
  }
}
