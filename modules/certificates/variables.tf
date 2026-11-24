variable "zone_id" {
  type        = string
  description = "Cloudflare Zone ID whose edge and origin certificates this module manages."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.zone_id))
    error_message = "zone_id must be a 32-character hexadecimal Cloudflare zone identifier."
  }
}

variable "zone_name" {
  type        = string
  description = <<-EOT
    Apex domain of the zone (e.g. example.com).

    Used to qualify relative hostnames in `certificate_packs` and
    `origin_ca_certificates`, to add the apex to every certificate pack (which
    Cloudflare requires), and to reject a hostname that belongs to another zone.
  EOT

  # Labels accept lowercase Unicode letters, not just ASCII
  validation {
    condition     = can(regex("^([0-9\\p{Ll}\\p{Lo}\\p{M}]([0-9\\p{Ll}\\p{Lo}\\p{M}-]{0,61}[0-9\\p{Ll}\\p{Lo}\\p{M}])?\\.)+[\\p{Ll}\\p{Lo}]{2,}$", var.zone_name))
    error_message = "zone_name must be a valid apex domain (e.g. example.com), lowercase, no scheme or path."
  }

  # Cloudflare returns IDN names in Unicode, so a punycode value would never
  # match what is read back and every plan would show drift.
  validation {
    condition     = !can(regex("(^|\\.)xn--", var.zone_name))
    error_message = "zone_name must use the Unicode form of an IDN (e.g. café-example.fr), not punycode - Cloudflare returns the Unicode name, so a punycode value shows drift on every plan."
  }
}

# -----------------------------------------------------------------------------
# Universal SSL
# -----------------------------------------------------------------------------
variable "universal_ssl_enabled" {
  type        = bool
  default     = null
  description = <<-EOT
    Universal SSL, the free edge certificate Cloudflare orders for the apex and
    first-level wildcard. Null leaves the setting unmanaged.

    false removes the Universal certificate from the edge and stops it being
    renewed. Any hostname with no other valid edge certificate then fails every
    new TLS handshake, so the module refuses false unless this same instance
    also orders a certificate pack or uploads a custom certificate. That proves
    something else is configured, not that it covers every hostname: check each
    pack's `status` is `active` before applying the change that disables this.

    Terraform cannot delete this setting, so going back to null leaves it as
    last applied. To turn Universal SSL back on, set true.
  EOT
}

# -----------------------------------------------------------------------------
# Total TLS
# -----------------------------------------------------------------------------
variable "total_tls" {
  type = object({
    enabled               = bool
    certificate_authority = optional(string)
  })
  default     = null
  description = <<-EOT
    Total TLS: an advanced certificate ordered automatically for every proxied
    A, AAAA and CNAME record not already covered by Universal SSL. Null leaves
    the setting unmanaged.

    - `enabled`               - On or off. Declaring false is not a no-op: it
                                makes a dashboard change show as drift.
    - `certificate_authority` - google, lets_encrypt or ssl_com. Null lets
                                Cloudflare choose.

    Requires an Advanced Certificate Manager subscription and a full (not
    partial/CNAME) DNS setup. Cloudflare does not issue Total TLS certificates
    for hostnames used by Load Balancing, Tunnel or Spectrum.

    Terraform cannot delete this setting, so going back to null leaves it as
    last applied. To turn Total TLS off, set enabled = false.
  EOT

  validation {
    condition = (
      var.total_tls == null
      ? true
      : var.total_tls.certificate_authority == null || contains(["google", "lets_encrypt", "ssl_com"], coalesce(try(var.total_tls.certificate_authority, null), "-"))
    )
    error_message = "total_tls.certificate_authority must be one of: google, lets_encrypt, ssl_com, or null to let Cloudflare choose."
  }
}

# -----------------------------------------------------------------------------
# Advanced Certificate Manager
# -----------------------------------------------------------------------------
variable "certificate_packs" {
  type = map(object({
    hosts                 = list(string)
    certificate_authority = string
    validation_method     = string
    validity_days         = number
    cloudflare_branding   = optional(bool, false)
  }))
  default     = {}
  description = <<-EOT
    Advanced certificate packs, keyed by a logical name. Requires Advanced
    Certificate Manager on the zone.

    - `hosts`                 - Names the certificate covers: relative labels
                                ("www"), "*" for the first-level wildcard, "@"
                                for the apex, or names ending in the zone's
                                domain. The apex is always added, because
                                Cloudflare rejects a pack without it. At most 50
                                names including the apex.
    - `certificate_authority` - google, lets_encrypt or ssl_com.
    - `validation_method`     - txt, http or email. A wildcard needs txt.
    - `validity_days`         - 14, 30, 90 or 365. Let's Encrypt issues 90 only,
                                Google Trust Services 14, 30 or 90, SSL.com 14,
                                30 or 90, and 365 for Enterprise zones.
    - `cloudflare_branding`   - Adds a sni.cloudflaressl.com common name. Needed
                                where any hostname is longer than 64 characters.

    Cloudflare cannot change a pack once ordered, so any edit replaces it. The
    replacement is ordered before the old pack is deleted, so the hostnames stay
    covered while it validates.
  EOT

  validation {
    condition     = alltrue([for key in keys(var.certificate_packs) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "certificate_packs keys must be lowercase alphanumeric with underscores - they become resource addresses."
  }

  validation {
    condition = alltrue([
      for pack in var.certificate_packs : contains(["google", "lets_encrypt", "ssl_com"], pack.certificate_authority)
    ])
    error_message = "certificate_packs[*].certificate_authority must be one of: google, lets_encrypt, ssl_com."
  }

  validation {
    condition = alltrue([
      for pack in var.certificate_packs : contains(["txt", "http", "email"], pack.validation_method)
    ])
    error_message = "certificate_packs[*].validation_method must be one of: txt, http, email."
  }

  validation {
    condition = alltrue([
      for pack in var.certificate_packs : contains([14, 30, 90, 365], pack.validity_days)
    ])
    error_message = "certificate_packs[*].validity_days must be one of: 14, 30, 90, 365."
  }

  validation {
    condition = alltrue(flatten([
      for pack in var.certificate_packs : [for host in pack.hosts : trimspace(host) != ""]
    ]))
    error_message = "certificate_packs[*].hosts must not contain an empty name."
  }
}

# -----------------------------------------------------------------------------
# Custom certificates
# -----------------------------------------------------------------------------
variable "custom_certificates" {
  type = map(object({
    bundle_method   = optional(string, "ubiquitous")
    type            = optional(string, "sni_custom")
    geo_restriction = optional(string)
  }))
  default     = {}
  description = <<-EOT
    Custom (uploaded) edge certificates, keyed by a logical name. The material
    for each key is in `custom_certificate_material`, under the same key.
    Business and Enterprise zones only.

    - `bundle_method`   - ubiquitous (default; chain most likely to verify on
                          old clients), optimal (shortest chain) or force (the
                          chain exactly as uploaded).
    - `type`            - sni_custom (default) or legacy_custom, which also
                          serves clients that send no SNI. A zone gets one
                          legacy slot.
    - `geo_restriction` - us, eu or highest_security: keep the private key in
                          those data centres only. Enterprise.

    Cloudflare does not renew an uploaded certificate. Watch `expires_on` in
    the `custom_certificates` output and replace the material before then.
    New material replaces the certificate, uploading the new one before the old
    one is deleted, so a rotation needs one free slot in the zone's quota. A
    zone has one legacy_custom slot, so a legacy certificate cannot be rotated
    this way; the upload fails and the old certificate stays.
  EOT

  validation {
    condition     = alltrue([for key in keys(var.custom_certificates) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "custom_certificates keys must be lowercase alphanumeric with underscores - they become resource addresses."
  }

  validation {
    condition = alltrue([
      for cert in var.custom_certificates : contains(["ubiquitous", "optimal", "force"], cert.bundle_method)
    ])
    error_message = "custom_certificates[*].bundle_method must be one of: ubiquitous, optimal, force."
  }

  validation {
    condition = alltrue([
      for cert in var.custom_certificates : contains(["sni_custom", "legacy_custom"], cert.type)
    ])
    error_message = "custom_certificates[*].type must be sni_custom or legacy_custom."
  }

  validation {
    condition = alltrue([
      for cert in var.custom_certificates : cert.geo_restriction == null || contains(["us", "eu", "highest_security"], coalesce(cert.geo_restriction, "-"))
    ])
    error_message = "custom_certificates[*].geo_restriction must be us, eu, highest_security or null."
  }
}

variable "custom_certificate_material" {
  type = map(object({
    certificate = string
    private_key = string
  }))
  default     = {}
  sensitive   = true
  description = <<-EOT
    PEM certificate (leaf first, then any intermediates) and private key for
    each entry in `custom_certificates`, under the same key. Every key here
    must have an entry there and the other way round.

    The private key reaches Terraform state and any saved plan in plain text,
    because Terraform records what it sent. Anyone holding either can serve
    the zone's hostnames as though they were the zone.
  EOT
}

# -----------------------------------------------------------------------------
# Origin CA
# -----------------------------------------------------------------------------
variable "origin_ca_certificates" {
  type = map(object({
    hostnames          = list(string)
    csr                = string
    request_type       = string
    requested_validity = number
  }))
  default     = {}
  description = <<-EOT
    Cloudflare Origin CA certificates, keyed by a logical name: certificates
    for the ORIGIN server, trusted by the Cloudflare edge and by nothing else.

    - `hostnames`          - Relative labels, "*", "@" or names ending in the
                             zone's domain. Qualified like certificate_packs
                             hosts, but the apex is not added. At most 200.
    - `csr`                - PEM certificate signing request. Generate the key
                             and CSR on the origin, so the private key never
                             leaves it; it never passes through Terraform.
    - `request_type`       - origin-rsa or origin-ecc. Must match the key type
                             in the CSR.
    - `requested_validity` - 7, 30, 90, 365, 730, 1095 or 5475 days.

    An issued certificate cannot be changed, and deleting one revokes it.
    Terraform would normally replace a changed certificate, revoking the one
    the origin is still serving. The module refuses that instead: a change to
    csr, hostnames or request_type on an existing key fails the plan. To rotate,
    add an entry under a new key, install its certificate on the origin, then
    remove the old entry. A change to `requested_validity` alone is ignored and
    does not fail the plan.

    Only valid for proxied traffic with SSL mode full or strict. A visitor
    reaching the origin directly, or through a DNS-only record, gets an
    untrusted-certificate error. Cloudflare sends no expiry notification.
  EOT

  validation {
    condition     = alltrue([for key in keys(var.origin_ca_certificates) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "origin_ca_certificates keys must be lowercase alphanumeric with underscores - they become resource addresses."
  }

  validation {
    condition = alltrue([
      for cert in var.origin_ca_certificates : contains(["origin-rsa", "origin-ecc"], cert.request_type)
    ])
    error_message = "origin_ca_certificates[*].request_type must be origin-rsa or origin-ecc, matching the key type in the CSR."
  }

  validation {
    condition = alltrue([
      for cert in var.origin_ca_certificates : contains([7, 30, 90, 365, 730, 1095, 5475], cert.requested_validity)
    ])
    error_message = "origin_ca_certificates[*].requested_validity must be one of: 7, 30, 90, 365, 730, 1095, 5475."
  }

  validation {
    condition = alltrue([
      for cert in var.origin_ca_certificates : can(regex("-----BEGIN (NEW )?CERTIFICATE REQUEST-----", cert.csr))
    ])
    error_message = "origin_ca_certificates[*].csr must be a PEM certificate signing request, beginning with a -----BEGIN CERTIFICATE REQUEST----- line."
  }

  # The CSR is committed in the account tree. A private key pasted alongside it
  # would be committed with it, so this fails without echoing the value.
  validation {
    condition = alltrue([
      for cert in var.origin_ca_certificates : !can(regex("PRIVATE KEY", cert.csr))
    ])
    error_message = "An origin_ca_certificates csr contains a PRIVATE KEY block. Remove it now, treat the key as compromised and generate a new one: only the CERTIFICATE REQUEST block belongs here."
  }

  validation {
    condition = alltrue(flatten([
      for cert in var.origin_ca_certificates : [for host in cert.hostnames : trimspace(host) != ""]
    ]))
    error_message = "origin_ca_certificates[*].hostnames must not contain an empty name."
  }
}
