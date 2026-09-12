# Layer origin_pulls - Authenticated Origin Pulls, the mutual TLS between the
# Cloudflare edge and the origin.
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

    This layer reads `domain_name` and nothing else - it is what
    data.cloudflare_zone filters on to turn an origin_pulls key into a zone ID,
    and what qualifies a relative hostname.

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
# Authenticated Origin Pulls
# -----------------------------------------------------------------------------
variable "origin_pulls" {
  description = <<-EOT
    Authenticated Origin Pulls per zone, keyed by the same zone key as
    var.zones. A zone with no entry here is left exactly as Cloudflare has it -
    this layer writes nothing for a zone it was not given.

    - `enabled`         - Zone-level Authenticated Origin Pulls. Covers every
                          hostname in the zone. Defaults to
                          default_zone_level_enabled.
    - `certificate_key` - Key into var.origin_pull_certificates for a client
                          certificate of your own to present zone-wide. Omit to
                          use the certificate Cloudflare presents by default,
                          which every Cloudflare customer's edge also presents -
                          see allow_shared_cloudflare_certificate.
    - `hostnames`       - Per-hostname associations, each binding one hostname
                          to one certificate. This is what gives api.example.com
                          a certificate its origin alone trusts while the rest of
                          the zone keeps the zone-level posture. Where both
                          cover a hostname, Cloudflare applies the per-hostname
                          association.
        - `hostname`        - A relative label ("api") or a name ending in the
                              zone's domain. Qualified against the zone, and
                              rejected if it belongs to another one.
        - `enabled`         - Whether the edge presents the certificate on this
                              hostname's origin connections. Default true; false
                              parks the association without deleting it.
        - `certificate_key` - Key into var.origin_pull_certificates.
        - `certificate_id`  - ID of a certificate already uploaded to the zone
                              outside Terraform. Mutually exclusive with
                              certificate_key.

    Turning any of this on changes nothing at the origin by itself: the origin
    has to be configured to require and verify a client certificate. Apply this
    first, install the origin_trust_bundle output, and switch the origin to
    require a certificate last. Doing it the other way round fails every request
    in between.
  EOT
  type = map(object({
    enabled         = optional(bool)
    certificate_key = optional(string)
    hostnames = optional(list(object({
      hostname        = string
      enabled         = optional(bool, true)
      certificate_key = optional(string)
      certificate_id  = optional(string)
    })), [])
  }))
  default = {}
}

variable "origin_pull_certificates" {
  type = map(object({
    certificate = string
    private_key = string
  }))
  default     = {}
  sensitive   = true
  description = <<-EOT
    Client certificates, as PEM, keyed by the logical name that a
    `certificate_key` in var.origin_pulls refers to. One key may be referenced by
    more than one zone or hostname; each zone is only ever handed the
    certificates its own entries name.

    THIS VARIABLE IS NEVER SET FROM A FILE. It arrives from the pipeline as
    TF_VAR_origin_pull_certificates, mapped in _terraform-run.yml from the
    <account>-plan environment's TF_VAR_ORIGIN_PULL_CERTIFICATES secret - the
    plan environment, not the apply one, because apply runs a saved plan file and
    never re-reads TF_VAR_:

      TF_VAR_origin_pull_certificates={"api_origin":{"certificate":"-----BEGIN CERTIFICATE-----\n...","private_key":"-----BEGIN PRIVATE KEY-----\n..."}}

    Three things follow, and none of them is optional reading.

    A private key written into a .tfvars is committed the moment somebody runs
    `git add .`, and .gitignore will not save you: accounts/*/*.tfvars is
    explicitly un-ignored so account trees can be committed. CI greps committed
    tfvars for credential-shaped strings, but that is a backstop, not a control.

    The key reaches Terraform state and the saved plan in plain text, because
    Terraform records what it sent. Whoever holds either can present this
    certificate and be accepted by the origin as the Cloudflare edge. See the
    state warning in terraform.tf.

    The newlines matter. PEM is line-structured, and a value flattened to one
    line is rejected by Cloudflare. Encode the file with its line breaks intact -
    `jq -Rs .` over the .pem produces exactly the escaped form above.
  EOT
}

# -----------------------------------------------------------------------------
# Platform defaults - see defaults.auto.tfvars
# -----------------------------------------------------------------------------
variable "default_zone_level_enabled" {
  type        = bool
  default     = false
  description = "Zone-level Authenticated Origin Pulls for a zone in var.origin_pulls that does not set `enabled`. Off by default: switching it on before the origin trusts the certificate is harmless, but it is still a change to what the edge sends every origin in the zone, and it should be asked for rather than inherited."
}

variable "allow_shared_cloudflare_certificate" {
  type        = bool
  default     = true
  description = <<-EOT
    Whether a zone may run Authenticated Origin Pulls on the certificate
    Cloudflare presents by default, rather than one uploaded through
    var.origin_pull_certificates.

    The default certificate is presented by the Cloudflare edge for every
    customer on the platform. An origin that trusts it therefore accepts any
    request proxied through any Cloudflare account, not only this one - so on its
    own it proves the connection came through Cloudflare, not that it came
    through you. That is still worth having as a filter in front of an origin
    that would otherwise accept anything, which is why this defaults to true and
    a `check` warns instead of failing.

    Set false on an account where an origin is relied on to identify the tenant -
    a PCI cardholder-data environment, a shared origin serving several tenants -
    and every zone must then bring its own certificate.
  EOT
}

variable "cloudflare_origin_pull_ca_certificate" {
  type        = string
  default     = null
  description = <<-EOT
    Cloudflare's public Origin Pull CA, as PEM. Null - the normal case - uses the
    copy vendored at ca/cloudflare_origin_pull_ca.pem in this layer, which is
    where it should be refreshed when Cloudflare rotates it. See ca/README.md.

    Set it only to get ahead of a rotation on one account before the template
    carrying the new copy is bumped.

    It reaches the origin_trust_bundle output only for zones that actually rely
    on Cloudflare's default certificate. A zone with a certificate of its own
    gets a bundle holding that certificate alone, because adding the CA would
    make its origin accept the default certificate too - the exact thing the
    dedicated certificate was uploaded to stop.
  EOT

  validation {
    condition     = var.cloudflare_origin_pull_ca_certificate == null || can(regex("-----BEGIN CERTIFICATE-----", coalesce(var.cloudflare_origin_pull_ca_certificate, "-")))
    error_message = "cloudflare_origin_pull_ca_certificate must be PEM, beginning with a -----BEGIN CERTIFICATE----- line, or null to use the copy vendored in this layer."
  }
}
