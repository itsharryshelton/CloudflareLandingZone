variable "zone_id" {
  type        = string
  description = "Cloudflare Zone ID whose Authenticated Origin Pulls configuration this module manages."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.zone_id))
    error_message = "zone_id must be a 32-character hexadecimal Cloudflare zone identifier."
  }
}

variable "zone_name" {
  type        = string
  description = <<-EOT
    Apex domain of the zone (e.g. example.com).

    Used to qualify a relative hostname in `hostnames` and to reject one that
    belongs to a different zone. Cloudflare stores per-hostname associations
    fully-qualified, so "api" would otherwise read back as "api.example.com"
    and show drift on every plan.
  EOT

  # Labels accept lowercase Unicode letters, not just ASCII
  validation {
    condition     = can(regex("^([0-9\\p{Ll}\\p{Lo}\\p{M}]([0-9\\p{Ll}\\p{Lo}\\p{M}-]{0,61}[0-9\\p{Ll}\\p{Lo}\\p{M}])?\\.)+[\\p{Ll}\\p{Lo}]{2,}$", var.zone_name))
    error_message = "zone_name must be a valid apex domain (e.g. example.com), lowercase, no scheme or path."
  }

  # Cloudflare normalises IDN zone names to Unicode on read, so a punycode name
  # never matches what the API returns, and every plan then shows drift on the
  # records this qualifies.
  validation {
    condition     = !can(regex("(^|\\.)xn--", var.zone_name))
    error_message = "zone_name must use the Unicode form of an IDN (e.g. café-example.fr), not punycode - Cloudflare returns the Unicode name, so a punycode value shows drift on every plan."
  }
}

variable "enabled" {
  type        = bool
  default     = false
  description = <<-EOT
    Zone-level Authenticated Origin Pulls: when on, Cloudflare presents a client
    certificate on every origin connection for every hostname in the zone.

    This is a switch on Cloudflare's side only. It does not make the origin
    check anything - the origin has to be configured to require and verify the
    certificate, and until it is, turning this on changes no behaviour. Do it in
    that order: apply this, install `origin_trust_bundle` at the origin, and
    only then set the origin to require a client certificate. The reverse order
    fails every request in between.

    Independent of the per-hostname associations in `hostnames`. Where both
    cover a hostname, the per-hostname association is what Cloudflare applies.

    Requires the zone's SSL mode to be `full` or `strict` - the zones layer owns
    that setting. On `flexible` there is no TLS connection to the origin to put
    a client certificate on.
  EOT
}

variable "zone_certificate" {
  type = object({
    certificate = string
    private_key = string
  })
  default     = null
  sensitive   = true
  description = <<-EOT
    A client certificate of your own for zone-level Authenticated Origin Pulls,
    as PEM. Leave null to use the certificate Cloudflare presents by default.

    Upload one where it matters who is connecting, not just that Cloudflare is.
    Cloudflare's default certificate is presented by the edge for every customer
    on the platform, so an origin that trusts it accepts a connection proxied
    through any Cloudflare account, not only yours.

    Uploading a certificate does not by itself switch zone-level Authenticated
    Origin Pulls on - `enabled` does that.

    The private key reaches Terraform state in plain text, because Terraform
    records what it sent. Treat this layer's state and any saved plan of it as
    holding the key itself.
  EOT
}

variable "hostname_certificates" {
  type = map(object({
    certificate = string
    private_key = string
  }))
  default     = {}
  sensitive   = true
  description = <<-EOT
    Client certificates for per-hostname Authenticated Origin Pulls, as PEM,
    keyed by a logical name that `hostnames[*].certificate_key` refers to.

    Per-hostname associations are the reason this module exists separately from
    zone_base: one critical hostname can be given a dedicated certificate that
    its origin - and only its origin - trusts, while the rest of the zone keeps
    the zone-level posture.

    A certificate here is uploaded to the zone whether or not a hostname refers
    to it; an unreferenced one is reported rather than silently uploaded, since
    an unused private key in state is one nobody rotates and nobody misses.

    Same state warning as `zone_certificate`: the private keys are recorded in
    plain text.
  EOT
}

variable "hostnames" {
  type = list(object({
    hostname        = string
    enabled         = optional(bool, true)
    certificate_key = optional(string)
    certificate_id  = optional(string)
  }))
  default     = []
  description = <<-EOT
    Per-hostname Authenticated Origin Pulls associations.
      - hostname        : a relative label ("api") or a fully-qualified name.
                          Relative names are qualified with `zone_name` by the
                          module. Must belong to this zone.
      - enabled         : whether Cloudflare presents the certificate on
                          connections to this hostname's origin. Defaults to
                          true; set false to keep the association but stop
                          using it, which is the reversible way to turn a
                          hostname off.
      - certificate_key : key into `hostname_certificates` for a certificate
                          this module uploads.
      - certificate_id  : the ID of a certificate already uploaded to this zone
                          outside Terraform. Mutually exclusive with
                          certificate_key.

    Entries are keyed on the qualified hostname, so reordering the list never
    forces a replacement.
  EOT

  validation {
    condition = alltrue([
      for entry in var.hostnames : trimspace(entry.hostname) != ""
    ])
    error_message = "Each hostnames entry must set a non-empty `hostname`."
  }

  validation {
    condition = alltrue([
      for entry in var.hostnames :
      entry.certificate_key == null || entry.certificate_id == null
    ])
    error_message = "A hostnames entry sets both `certificate_key` and `certificate_id`. Pick one: certificate_key for a certificate this module uploads, certificate_id for one that already exists in the zone."
  }

  validation {
    condition = alltrue([
      for entry in var.hostnames :
      entry.certificate_id == null || can(regex("^[0-9a-f-]{16,64}$", coalesce(entry.certificate_id, "-")))
    ])
    error_message = "hostnames[*].certificate_id must be a Cloudflare certificate identifier (hexadecimal, hyphens allowed)."
  }
}

variable "origin_pull_ca_certificate" {
  type        = string
  default     = ""
  description = <<-EOT
    Cloudflare's public Origin Pull CA, as PEM. Included verbatim in the
    `origin_trust_bundle` output.

    Only relevant while any hostname is served through the certificate
    Cloudflare presents by default: that certificate chains to this CA, so this
    is what an origin has to trust to verify it. Where every hostname uses a
    certificate uploaded here instead, leave it empty - including it would make
    the origin accept Cloudflare's default certificate as well, which is the
    whole thing a dedicated certificate was meant to stop.

    Supplied rather than embedded because Cloudflare rotates it and a copy
    baked into a module goes stale without anybody noticing.
  EOT

  validation {
    condition     = trimspace(var.origin_pull_ca_certificate) == "" || can(regex("-----BEGIN CERTIFICATE-----", var.origin_pull_ca_certificate))
    error_message = "origin_pull_ca_certificate must be PEM, beginning with a -----BEGIN CERTIFICATE----- line, or empty."
  }
}
