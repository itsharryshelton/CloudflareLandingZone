# Layer certificates - edge and origin TLS certificates: Universal SSL, Total
# TLS, Advanced Certificate Manager packs, custom certificates and Origin CA.
#
# The zone inventory and the account ID are declared with the same shape and the
# same text as in layers/zones, because accounts/<account>/zones.tfvars and
# account.tfvars are passed to both and Terraform rejects a var file containing a
# variable the root module does not declare. See .github/scripts/tf-varfiles.sh.

variable "cloudflare_account_id" {
  type        = string
  description = <<-EOT
    Cloudflare Account ID this layer run targets. Supplied from
    accounts/<account>/account.tfvars, or overridden with
    TF_VAR_cloudflare_account_id.
  EOT

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "zones" {
  description = <<-EOT
    Zone inventory: the logical key => domain name mapping for this account,
    from accounts/<account>/zones.tfvars. Shared verbatim with every layer that
    resolves a zone key to a zone ID.

    This layer reads `domain_name` and nothing else. The zone's plan and setup
    type are read from Cloudflare instead, because the gates here depend on what
    the zone is actually entitled to.

    - `domain_name` - The apex domain (e.g. example.com).
    - `zone_tier`   - (Optional) Declared only so this file remains passable to
                      this layer; a var file carrying an attribute the root
                      module does not accept is rejected outright. Nothing here
                      reads it.
  EOT
  type = map(object({
    domain_name = string
    zone_tier   = optional(string)
  }))

  validation {
    condition     = alltrue([for key in keys(var.zones) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "zones keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
  }

  validation {
    condition = alltrue([
      for zone in var.zones : zone.zone_tier == null || contains([
        "free", "lite", "pro", "pro_plus", "business", "enterprise",
        "partners_free", "partners_pro", "partners_business",
        "partners_enterprise", "partners_ent",
      ], coalesce(zone.zone_tier, "free"))
    ])
    error_message = "zones[*].zone_tier must be one of: free, lite, pro, pro_plus, business, enterprise, partners_free, partners_pro, partners_business, partners_enterprise, partners_ent."
  }

  validation {
    condition     = length(distinct([for z in var.zones : lower(z.domain_name)])) == length(var.zones)
    error_message = "Each zones entry must have a distinct domain_name; Cloudflare allows one zone per domain per account."
  }
}

# -----------------------------------------------------------------------------
# Certificates
# -----------------------------------------------------------------------------
variable "certificates" {
  description = <<-EOT
    Certificate configuration per zone, keyed by the same zone key as
    var.zones. A zone with no entry is left exactly as Cloudflare has it, and so
    is any part of an entry left unset.

    - `universal_ssl`          - true or false to manage Universal SSL; omit to
                                 leave it alone. false needs a certificate pack
                                 or custom certificate on the same zone, and
                                 every hostname without one stops serving TLS.
                                 Terraform cannot delete the setting: to turn
                                 it back on, set true rather than removing it.
    - `total_tls`              - { enabled, certificate_authority }. A
                                 certificate for every proxied hostname that
                                 Universal SSL does not cover. Needs Advanced
                                 Certificate Manager and a full DNS setup.
                                 Terraform cannot delete the setting: to turn it
                                 off, set enabled = false rather than removing
                                 it.
    - `certificate_packs`      - Advanced certificates (Advanced Certificate
                                 Manager), keyed by name:
        - `hosts`                 - Relative labels, "*", "@" or names in the
                                    zone. The apex is always added. Max 50.
        - `certificate_authority` - google, lets_encrypt or ssl_com. Default
                                    default_certificate_authority.
        - `validation_method`     - txt, http or email. Default
                                    default_validation_method. Wildcards need
                                    txt.
        - `validity_days`         - 14, 30, 90 or 365, as the CA allows.
                                    Default default_validity_days.
        - `cloudflare_branding`   - Needed for a hostname over 64 characters.
    - `custom_certificates`    - Uploaded certificates, keyed by name. Business
                                 and Enterprise, up to the zone's quota:
        - `certificate_key`  - Key into var.custom_certificates for the PEM
                               certificate and private key.
        - `bundle_method`    - ubiquitous, optimal or force. Default
                               default_bundle_method.
        - `type`             - sni_custom (default) or legacy_custom.
        - `geo_restriction`  - us, eu or highest_security. Enterprise.
                               New material replaces the certificate, uploading
                               the new one first, so rotation needs a free slot
                               in the quota.
    - `origin_ca_certificates` - Origin CA certificates for the origin server,
                                 trusted by Cloudflare only, keyed by name:
        - `hostnames`          - Relative labels, "*", "@" or names in the zone.
                                 Max 200.
        - `csr`                - PEM CSR, generated on the origin. Committed
                                 here: a CSR is public. The private key is not,
                                 and never goes anywhere near this file.
        - `request_type`       - origin-rsa or origin-ecc, matching the CSR.
        - `requested_validity` - Days. Default default_origin_ca_validity_days.
                                 Fixed once issued.

    Origin CA certificates cannot be changed. Changing csr, hostnames or
    request_type on an existing key fails the plan. To rotate, add a new key,
    install it on the origin, then remove the old key, which revokes it.
  EOT
  type = map(object({
    universal_ssl = optional(bool)
    total_tls = optional(object({
      enabled               = bool
      certificate_authority = optional(string)
    }))
    certificate_packs = optional(map(object({
      hosts                 = list(string)
      certificate_authority = optional(string)
      validation_method     = optional(string)
      validity_days         = optional(number)
      cloudflare_branding   = optional(bool, false)
    })), {})
    custom_certificates = optional(map(object({
      certificate_key = string
      bundle_method   = optional(string)
      type            = optional(string, "sni_custom")
      geo_restriction = optional(string)
    })), {})
    origin_ca_certificates = optional(map(object({
      hostnames          = list(string)
      csr                = string
      request_type       = string
      requested_validity = optional(number)
    })), {})
  }))
  default = {}

  # Checked here as well as in the module, because this is the committed file a
  # private key would be pasted into, and the operator should see it against
  # their own input rather than a module address.
  validation {
    condition = alltrue(flatten([
      for zone in var.certificates : [
        for cert in zone.origin_ca_certificates : !can(regex("PRIVATE KEY", cert.csr))
      ]
    ]))
    error_message = "An origin_ca_certificates csr in this account tree contains a PRIVATE KEY block. Remove it before committing, treat that key as compromised and generate a new key and CSR on the origin. Only the CERTIFICATE REQUEST block belongs in certificates.tfvars."
  }
}

variable "custom_certificates" {
  type = map(object({
    certificate = string
    private_key = string
  }))
  default     = {}
  sensitive   = true
  description = <<-EOT
    Custom edge certificates, as PEM, keyed by the name a `certificate_key` in
    var.certificates refers to. `certificate` is the leaf followed by any
    intermediates.

    THIS VARIABLE IS NEVER SET FROM A FILE. It arrives from the pipeline as
    TF_VAR_custom_certificates, mapped in _terraform-run.yml from the
    <account>-plan environment's TF_VAR_CUSTOM_CERTIFICATES secret - the plan
    environment, not the apply one, because apply runs a saved plan file and
    never re-reads TF_VAR_:

      TF_VAR_custom_certificates={"www_2027":{"certificate":"-----BEGIN CERTIFICATE-----\n...","private_key":"-----BEGIN PRIVATE KEY-----\n..."}}

    The private key reaches Terraform state and the saved plan in plain text.
    Whoever holds either can serve the zone's hostnames as the zone. See the
    state warning in terraform.tf.

    PEM is line-structured, and a value flattened to one line is rejected by
    Cloudflare. Build the value with `jq -n --rawfile` rather than pasting.
  EOT
}

# -----------------------------------------------------------------------------
# Platform defaults - see defaults.auto.tfvars
# -----------------------------------------------------------------------------
variable "default_certificate_authority" {
  type        = string
  default     = "google"
  description = "CA for a certificate pack that does not set `certificate_authority`: google, lets_encrypt or ssl_com."

  validation {
    condition     = contains(["google", "lets_encrypt", "ssl_com"], var.default_certificate_authority)
    error_message = "default_certificate_authority must be one of: google, lets_encrypt, ssl_com."
  }
}

variable "default_validation_method" {
  type        = string
  default     = "txt"
  description = "Domain validation method for a certificate pack that does not set `validation_method`. txt works for wildcards and needs no origin change, and Cloudflare publishes the record itself on a full DNS setup."

  validation {
    condition     = contains(["txt", "http", "email"], var.default_validation_method)
    error_message = "default_validation_method must be one of: txt, http, email."
  }
}

variable "default_validity_days" {
  type        = number
  default     = 90
  description = "Validity for a certificate pack that does not set `validity_days`. 90 is the one period every CA offers; Cloudflare renews packs itself, so a shorter one costs nothing but more frequent renewals."

  validation {
    condition     = contains([14, 30, 90, 365], var.default_validity_days)
    error_message = "default_validity_days must be one of: 14, 30, 90, 365."
  }
}

variable "default_bundle_method" {
  type        = string
  default     = "ubiquitous"
  description = "Chain for a custom certificate that does not set `bundle_method`. ubiquitous is the chain most likely to verify on old clients."

  validation {
    condition     = contains(["ubiquitous", "optimal", "force"], var.default_bundle_method)
    error_message = "default_bundle_method must be one of: ubiquitous, optimal, force."
  }
}

variable "default_origin_ca_validity_days" {
  type        = number
  default     = 365
  description = <<-EOT
    Validity for an Origin CA certificate that does not set
    `requested_validity`. Cloudflare's own default is 5475 (15 years).

    365 keeps a leaked origin key useful for a year rather than fifteen, at the
    cost of a yearly rotation, which Cloudflare sends no reminder for. Raise it
    in defaults.auto.tfvars, on a pull request that says why, where nobody would
    do that rotation.
  EOT

  validation {
    condition     = contains([7, 30, 90, 365, 730, 1095, 5475], var.default_origin_ca_validity_days)
    error_message = "default_origin_ca_validity_days must be one of: 7, 30, 90, 365, 730, 1095, 5475."
  }
}
