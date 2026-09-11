variable "account_id" {
  type        = string
  description = "Cloudflare Account ID whose device posture rules and service provider integrations this module manages."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "integrations" {
  type = list(object({
    name     = string
    type     = string
    interval = string
    config = optional(object({
      api_url              = optional(string)
      auth_url             = optional(string)
      client_id            = optional(string)
      client_secret        = optional(string)
      client_key           = optional(string)
      customer_id          = optional(string)
      access_client_id     = optional(string)
      access_client_secret = optional(string)
    }), {})
  }))
  default     = []
  description = <<-EOT
    Service provider integrations: the connections Cloudflare polls, on its own
    schedule, for what a third-party MDM or EDR thinks of each device. A
    service-to-service rule reads its result through one of these.

      - name     : display name, and this integration's identity here. Matched
                   lower-cased and trimmed. Rules refer to an integration by it.
      - type     : "intune", "crowdstrike_s2s", "kolide", "sentinelone_s2s",
                   "tanium_s2s", "workspace_one", "uptycs" or "custom_s2s".
      - interval : how often Cloudflare polls the provider, e.g. "10m" or "1h".
                   Minutes or hours, one unit.
      - config   : the provider's connection settings. Which fields a type needs:
                     intune          - client_id, customer_id (the Entra tenant ID),
                                       client_secret
                     crowdstrike_s2s - client_id, customer_id, api_url (the Falcon
                                       base URL), client_secret
                     kolide          - client_secret
                     sentinelone_s2s - api_url, client_secret (the API token)
                     tanium_s2s      - api_url (the Gateway GraphQL endpoint),
                                       client_secret
                     workspace_one   - client_id, api_url, auth_url, client_secret
                     uptycs          - api_url, customer_id, client_key,
                                       client_secret
                     custom_s2s      - api_url, access_client_id,
                                       access_client_secret (an Access service
                                       token protecting api_url)
                   client_secret, client_key and access_client_secret are
                   CREDENTIALS. The provider marks them sensitive; they still
                   reach Terraform state in plain text, because Terraform records
                   what it sent.

    Cloudflare tests the connection when the integration is created, so a wrong
    credential fails the apply rather than the plan. Uptycs can be connected but
    has no rule type in the provider, so nothing can evaluate it yet.
  EOT

  validation {
    condition     = alltrue([for i in var.integrations : trimspace(i.name) != ""])
    error_message = "Each integrations[*].name must be a non-empty display name."
  }

  validation {
    condition = length(distinct([
      for i in var.integrations : lower(trimspace(i.name))
    ])) == length(var.integrations)
    error_message = "integrations contains duplicate names. Names are compared lower-cased and trimmed, and they are how a rule refers to an integration - each must be uniquely named."
  }

  validation {
    condition = alltrue([
      for i in var.integrations : contains([
        "intune", "crowdstrike_s2s", "kolide", "sentinelone_s2s",
        "tanium_s2s", "workspace_one", "uptycs", "custom_s2s",
      ], i.type)
    ])
    error_message = "Each integrations[*].type must be one of intune, crowdstrike_s2s, kolide, sentinelone_s2s, tanium_s2s, workspace_one, uptycs, custom_s2s."
  }

  # One unit only, so the layer can compare an interval against a rule's
  # expiration without a duration parser.
  validation {
    condition     = alltrue([for i in var.integrations : can(regex("^[1-9][0-9]*(m|h)$", i.interval))])
    error_message = "Each integrations[*].interval must be a whole number of minutes or hours in one unit, such as \"10m\" or \"1h\"."
  }
}

variable "rules" {
  type = list(object({
    name             = string
    type             = string
    description      = optional(string)
    schedule         = optional(string)
    expiration       = optional(string)
    platforms        = optional(list(string), [])
    integration_name = optional(string)
    integration_id   = optional(string)
    input = optional(object({
      operating_system          = optional(string)
      path                      = optional(string)
      exists                    = optional(bool)
      sha256                    = optional(string)
      thumbprint                = optional(string)
      list_id                   = optional(string)
      domain                    = optional(string)
      operator                  = optional(string)
      version                   = optional(string)
      os_distro_name            = optional(string)
      os_distro_revision        = optional(string)
      os_version_extra          = optional(string)
      enabled                   = optional(bool)
      check_disks               = optional(list(string))
      require_all               = optional(bool)
      certificate_id            = optional(string)
      cn                        = optional(string)
      check_private_key         = optional(bool)
      extended_key_usage        = optional(list(string))
      subject_alternative_names = optional(list(string))
      locations = optional(object({
        paths        = optional(list(string))
        trust_stores = optional(list(string))
      }))
      update_window_days = optional(number)
      compliance_status  = optional(string)
      last_seen          = optional(string)
      os                 = optional(string)
      overall            = optional(string)
      sensor_config      = optional(string)
      state              = optional(string)
      version_operator   = optional(string)
      auth_state         = optional(list(string))
      eid_last_seen      = optional(string)
      risk_level         = optional(string)
      score_operator     = optional(string)
      total_score        = optional(number)
      active_threats     = optional(number)
      infected           = optional(bool)
      is_active          = optional(bool)
      network_status     = optional(string)
      operational_state  = optional(string)
      score              = optional(number)
    }), {})
  }))
  default     = []
  description = <<-EOT
    Device posture rules - the checks an Access or Gateway policy can require a
    device to have passed. Access and Gateway both reference a rule by its ID.

      - name             : display name, and this rule's identity here. Matched
                           lower-cased and trimmed.
      - type             : what is checked. Cloudflare One Client checks, run on
                           the device:
                             warp, gateway, os_version, disk_encryption, firewall,
                             antivirus, domain_joined, file, application,
                             serial_number, unique_client_id,
                             client_certificate_v2, client_certificate,
                             sentinelone, carbonblack, tanium (legacy, Access only)
                           Service provider checks, read through an integration:
                             intune, crowdstrike_s2s, kolide, sentinelone_s2s,
                             tanium_s2s, workspace_one, custom_s2s
      - description      : (Optional) shown in the dashboard.
      - schedule         : (Optional) how often the client re-checks, e.g. "5m".
                           Cloudflare's default is 5m and its minimum 1m. Client
                           checks only; a service provider check polls on its
                           integration's interval.
      - expiration       : (Optional) how long a result stays valid, e.g. "10m".
                           Unset, a result stands until the device reports again -
                           so a device that stops reporting keeps its last pass
                           indefinitely.
      - platforms        : (Optional) run only on these platforms: windows, mac,
                           linux, android, ios, chromeos. Empty runs everywhere.
      - integration_name : service provider checks only - an integration from
                           var.integrations of the same type.
      - integration_id   : service provider checks only - the same, for an
                           integration managed elsewhere. Exactly one of the two.
      - input            : what the check compares against. Per type:
                             os_version       - operating_system, operator, version
                                                (semver: "10.0.19045", not "10.0"),
                                                os_version_extra (Windows UBR),
                                                os_distro_name / os_distro_revision
                             disk_encryption  - require_all, or check_disks
                             firewall         - operating_system, enabled
                             antivirus        - operating_system, update_window_days
                             domain_joined    - operating_system, domain
                                                (case-sensitive)
                             file             - operating_system, path, exists,
                                                thumbprint, sha256
                             application,
                             sentinelone,
                             carbonblack      - operating_system, path, thumbprint,
                                                sha256
                             serial_number,
                             unique_client_id - list_id: a Zero Trust list of serial
                                                numbers or device IDs
                             client_certificate_v2
                                              - operating_system, certificate_id,
                                                locations, cn,
                                                subject_alternative_names,
                                                extended_key_usage,
                                                check_private_key
                             intune,
                             workspace_one    - compliance_status
                             crowdstrike_s2s  - overall, os, sensor_config, state,
                                                last_seen, version,
                                                version_operator, operator
                             kolide           - auth_state
                             sentinelone_s2s  - infected, active_threats,
                                                is_active, network_status,
                                                operational_state, operator
                             tanium_s2s       - total_score, score_operator,
                                                risk_level, eid_last_seen
                             custom_s2s       - score, score_operator
                           The integration's connection ID is filled in from
                           integration_name or integration_id, never set here.

    Kolide's issue_count input is not offered: Cloudflare has deprecated it and
    keeps a rule that uses it permanently disabled, which looks configured and
    enforces nothing.

    Deleting a rule that an Access or Gateway policy still names leaves that
    policy requiring a check nothing can pass. Remove the reference, apply, then
    remove the rule.
  EOT

  validation {
    condition     = alltrue([for r in var.rules : trimspace(r.name) != ""])
    error_message = "Each rules[*].name must be a non-empty display name."
  }

  validation {
    condition = length(distinct([
      for r in var.rules : lower(trimspace(r.name))
    ])) == length(var.rules)
    error_message = "rules contains duplicate names. Names are compared lower-cased and trimmed - each rule must be uniquely named."
  }

  validation {
    condition = alltrue([
      for r in var.rules : contains([
        "warp", "gateway", "os_version", "disk_encryption", "firewall",
        "antivirus", "domain_joined", "file", "application", "serial_number",
        "unique_client_id", "client_certificate", "client_certificate_v2",
        "sentinelone", "carbonblack", "tanium",
        "intune", "crowdstrike_s2s", "kolide", "sentinelone_s2s",
        "tanium_s2s", "workspace_one", "custom_s2s",
      ], r.type)
    ])
    error_message = "Each rules[*].type must be one of warp, gateway, os_version, disk_encryption, firewall, antivirus, domain_joined, file, application, serial_number, unique_client_id, client_certificate, client_certificate_v2, sentinelone, carbonblack, tanium, intune, crowdstrike_s2s, kolide, sentinelone_s2s, tanium_s2s, workspace_one, custom_s2s."
  }

  validation {
    condition = alltrue(flatten([
      for r in var.rules : [
        for d in [r.schedule, r.expiration] : can(regex("^[1-9][0-9]*(m|h)$", d))
        if d != null
      ]
    ]))
    error_message = "rules[*].schedule and rules[*].expiration must be a whole number of minutes or hours in one unit, such as \"5m\" or \"2h\". Cloudflare's minimum schedule is 1m."
  }

  validation {
    condition = alltrue(flatten([
      for r in var.rules : [
        for p in r.platforms : contains(["windows", "mac", "linux", "android", "ios", "chromeos"], p)
      ]
    ]))
    error_message = "Each rules[*].platforms entry must be one of windows, mac, linux, android, ios, chromeos."
  }

  # A rule scoped to one platform and checking another's OS matches no device,
  # and fails every device it is required of.
  validation {
    condition = alltrue([
      for r in var.rules :
      r.input.operating_system == null || length(r.platforms) == 0 || contains(r.platforms, coalesce(r.input.operating_system, "-"))
    ])
    error_message = "A rules[*] entry sets input.operating_system to a platform its platforms list excludes. The check would run on no device it is written for."
  }

  validation {
    condition = alltrue([
      for r in var.rules :
      contains(["intune", "crowdstrike_s2s", "kolide", "sentinelone_s2s", "tanium_s2s", "workspace_one", "custom_s2s"], r.type)
      ? (r.integration_name == null) != (r.integration_id == null)
      : r.integration_name == null && r.integration_id == null
    ])
    error_message = "Service provider rules (intune, crowdstrike_s2s, kolide, sentinelone_s2s, tanium_s2s, workspace_one, custom_s2s) need exactly one of integration_name and integration_id. Every other type runs on the device and must set neither."
  }

  # Cloudflare wants a semver, and treats "10.0" as unparseable rather than as
  # "10.0.0" - the check then fails on every device.
  validation {
    condition = alltrue([
      for r in var.rules :
      r.type != "os_version" || (
        r.input.operating_system != null && r.input.operator != null
        && can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", coalesce(r.input.version, "-")))
      )
    ])
    error_message = "Each os_version rule needs input.operating_system, input.operator and input.version, and version must be a full semver such as \"10.0.19045\" or \"14.4.0\" - Cloudflare does not read \"14.4\" as \"14.4.0\"."
  }

  validation {
    condition = alltrue([
      for r in var.rules :
      !contains(["file", "application", "sentinelone", "carbonblack"], r.type)
      || (r.input.operating_system != null && trimspace(coalesce(r.input.path, " ")) != "")
    ])
    error_message = "Each file, application, sentinelone and carbonblack rule needs input.operating_system and input.path - one rule per operating system, because the path differs between them."
  }

  validation {
    condition = alltrue([
      for r in var.rules :
      r.type != "disk_encryption" || r.input.require_all == true || length(coalesce(r.input.check_disks, [])) > 0
    ])
    error_message = "Each disk_encryption rule needs input.require_all = true or a non-empty input.check_disks. With neither it names no volume to check."
  }

  validation {
    condition = alltrue([
      for r in var.rules :
      !contains(["serial_number", "unique_client_id"], r.type) || trimspace(coalesce(r.input.list_id, " ")) != ""
    ])
    error_message = "Each serial_number and unique_client_id rule needs input.list_id - the Zero Trust list holding the serial numbers or device IDs."
  }

  validation {
    condition = alltrue([
      for r in var.rules :
      r.type != "domain_joined" || trimspace(coalesce(r.input.domain, " ")) != ""
    ])
    error_message = "Each domain_joined rule needs input.domain. It is compared case-sensitively."
  }

  validation {
    condition = alltrue([
      for r in var.rules :
      r.type != "firewall" || (r.input.operating_system != null && r.input.enabled != null)
    ])
    error_message = "Each firewall rule needs input.operating_system and input.enabled. enabled is not an on/off switch for the check: true passes a device whose firewall is running, false passes one whose firewall is off."
  }

  validation {
    condition = alltrue([
      for r in var.rules :
      r.type != "client_certificate_v2" || (r.input.operating_system != null && trimspace(coalesce(r.input.certificate_id, " ")) != "")
    ])
    error_message = "Each client_certificate_v2 rule needs input.operating_system and input.certificate_id - the UUID of the signing certificate uploaded to Cloudflare, which must be the certificate that directly issued the client certificate."
  }

  validation {
    condition = alltrue([
      for r in var.rules :
      !contains(["intune", "workspace_one"], r.type) || r.input.compliance_status != null
    ])
    error_message = "Each intune and workspace_one rule needs input.compliance_status, usually \"compliant\"."
  }

  validation {
    condition = alltrue([
      for r in var.rules :
      r.type != "kolide" || length(coalesce(r.input.auth_state, [])) > 0
    ])
    error_message = "Each kolide rule needs input.auth_state, e.g. [\"Good\"]. The older issue_count input is deprecated and leaves the rule disabled."
  }

  validation {
    condition = alltrue([
      for r in var.rules :
      r.type != "custom_s2s" || (r.input.score != null && r.input.score_operator != null)
    ])
    error_message = "Each custom_s2s rule needs input.score and input.score_operator - the 0-100 value the external API returns and how to compare against it."
  }
}
