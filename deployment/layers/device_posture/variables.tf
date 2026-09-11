# Layer device_posture - inputs.
#
# Config files:
#   accounts/<account>/account.tfvars        - the account ID, shared with every layer
#   accounts/<account>/device_posture.tfvars - posture rules and integrations
#
# Never from a file - the pipeline supplies this from the <account>-plan
# environment:
#   TF_VAR_device_posture_integration_secrets - service provider credentials

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare Account ID this layer run targets. Supplied from accounts/<account>/account.tfvars."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "device_posture_integrations" {
  description = <<-EOT
    Service provider integrations, keyed by a logical key: the connections
    Cloudflare polls for what a third-party MDM or EDR thinks of each device. A
    service provider rule reads through one by `integration_key`.

    The key is a handle. The `name` is identity: renaming it replaces the
    integration, and every rule reading through it with it.

    - `name`     - Display name in the dashboard.
    - `type`     - "intune", "crowdstrike_s2s", "kolide", "sentinelone_s2s",
                   "tanium_s2s", "workspace_one", "uptycs" or "custom_s2s".
    - `interval` - (Optional) How often Cloudflare polls, e.g. "10m" or "1h".
                   Falls back to var.default_integration_interval.
    - `config`   - The non-secret connection settings. What each type needs:
                     intune          - client_id (the app registration's
                                       Application ID), customer_id (the Entra
                                       tenant ID). The app registration needs
                                       Graph DeviceManagementManagedDevices.Read.All.
                     crowdstrike_s2s - client_id, customer_id, api_url (the Falcon
                                       base URL). The API client needs Hosts:Read and
                                       Zero Trust Assessment:Read.
                     kolide          - nothing
                     sentinelone_s2s - api_url, e.g. https://<tenant>.sentinelone.net
                     tanium_s2s      - api_url, the Gateway GraphQL endpoint
                     workspace_one   - client_id, api_url, auth_url (the region's
                                       token URL)
                     uptycs          - customer_id
                     custom_s2s      - api_url, access_client_id (an Access service
                                       token protecting api_url)
                   There is NO secret field here on purpose - see
                   var.device_posture_integration_secrets.

    Cloudflare tests the connection when the integration is created, so a bad
    credential fails the apply, not the plan. Uptycs can be connected, but the
    provider has no Uptycs rule type, so nothing can evaluate it yet.
  EOT
  type = map(object({
    name     = string
    type     = string
    interval = optional(string)
    config = optional(object({
      api_url          = optional(string)
      auth_url         = optional(string)
      client_id        = optional(string)
      customer_id      = optional(string)
      access_client_id = optional(string)
    }), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.device_posture_integrations) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "device_posture_integrations keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
  }

  validation {
    condition = length(distinct([
      for integration in var.device_posture_integrations : lower(trimspace(integration.name))
    ])) == length(var.device_posture_integrations)
    error_message = "Two device_posture_integrations entries share a name. The name is the integration's identity in Cloudflare, so each must be uniquely named."
  }
}

variable "device_posture_integration_secrets" {
  type = map(object({
    client_secret        = optional(string)
    client_key           = optional(string)
    access_client_secret = optional(string)
  }))
  default     = {}
  sensitive   = true
  description = <<-EOT
    Service provider credentials, keyed by the same key as
    var.device_posture_integrations:

      intune, crowdstrike_s2s, workspace_one,
      kolide, sentinelone_s2s, tanium_s2s  - client_secret (SentinelOne's is the
                                             service user's API token)
      uptycs                               - client_key and client_secret
      custom_s2s                           - access_client_secret

    THIS VARIABLE IS NEVER SET FROM A FILE. It arrives from the pipeline as
    TF_VAR_device_posture_integration_secrets, mapped in _terraform-run.yml from
    the <account>-plan environment's TF_VAR_DEVICE_POSTURE_INTEGRATION_SECRETS
    secret - the plan environment, not the apply one, because apply runs a saved
    plan file and never re-reads TF_VAR_:

      TF_VAR_device_posture_integration_secrets={"intune":{"client_secret":"<secret>"}}

    A credential written into a .tfvars is committed the moment somebody runs
    `git add .`, and .gitignore will not save you: accounts/*/*.tfvars is
    explicitly un-ignored so account trees can be committed.

    The value reaches Terraform state and the saved plan in plain text, because
    Terraform records what it sent. Each credential reads device inventory out of
    an MDM or EDR, so scope it read-only at the provider, give it an expiry, and
    rotate it by updating the environment secret and re-applying.
  EOT
}

variable "device_posture_rules" {
  description = <<-EOT
    Device posture rules, keyed by a logical key - the checks an Access policy
    (device_posture_ids in zerotrust.tfvars) or a Gateway policy
    (device_posture_check_ids in gateway.tfvars) can require. Both take the rule's
    ID from this layer's `device_posture_rule_ids` output; neither can read this
    state.

    The key is a handle. The `name` is identity: renaming it replaces the rule and
    changes its ID, and every policy still holding the old ID then requires a
    check that no longer exists.

    - `name`            - Display name in the dashboard.
    - `type`            - Cloudflare One Client checks, run on the device:
                            warp, gateway, os_version, disk_encryption, firewall,
                            antivirus, domain_joined, file, application,
                            serial_number, unique_client_id, client_certificate_v2,
                            client_certificate, sentinelone, carbonblack
                          Service provider checks, read through an integration:
                            intune, crowdstrike_s2s, kolide, sentinelone_s2s,
                            tanium_s2s, workspace_one, custom_s2s
                          Types in var.restricted_posture_rule_types are refused.
    - `description`     - (Optional) Shown in the dashboard.
    - `schedule`        - (Optional) Client re-check interval, e.g. "5m". Falls back
                          to var.default_posture_schedule. Minimum 1m.
    - `expiration`      - (Optional) How long a result stays valid. Falls back to
                          twice the polling period while var.derive_posture_expiration
                          is on. Shorter than twice the polling period fails the
                          plan: the result would lapse before it is refreshed, and
                          devices would fail intermittently.
    - `platforms`       - (Optional) windows, mac, linux, android, ios, chromeos.
                          Empty runs everywhere.
    - `integration_key` - Service provider checks: a key from
                          var.device_posture_integrations, of the same type.
    - `integration_id`  - The same, for an integration managed elsewhere. Exactly
                          one of the two.
    - `input`           - What the check compares against. The fields per type are
                          listed on the `rules` variable in modules/device_posture.
                          The common ones:
                            os_version       - operating_system, operator, version
                                               (full semver: "10.0.19045")
                            disk_encryption  - require_all = true, or check_disks
                            firewall         - operating_system, enabled = true
                            file/application - operating_system, path, thumbprint
                            serial_number    - list_id, a Zero Trust list of serials
                            intune           - compliance_status = "compliant"
                            crowdstrike_s2s  - overall, operator, e.g. ">=" and "70"

    Removing a rule an Access or Gateway policy still names leaves that policy
    requiring a check nothing can pass - and this layer applies before zerotrust,
    so removing both in one run deletes the rule first. Remove the reference,
    apply, then remove the rule.
  EOT
  type = map(object({
    name            = string
    type            = string
    description     = optional(string)
    schedule        = optional(string)
    expiration      = optional(string)
    platforms       = optional(list(string), [])
    integration_key = optional(string)
    integration_id  = optional(string)
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
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.device_posture_rules) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "device_posture_rules keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
  }

  validation {
    condition = length(distinct([
      for rule in var.device_posture_rules : lower(trimspace(rule.name))
    ])) == length(var.device_posture_rules)
    error_message = "Two device_posture_rules entries share a name. The name is the rule's identity in Cloudflare, so each must be uniquely named."
  }
}

# Platform defaults (defaults.auto.tfvars)
variable "default_posture_schedule" {
  type        = string
  default     = "5m"
  description = "How often the Cloudflare One Client re-runs a device check that names no schedule of its own. 5m is Cloudflare's own default; stating it keeps what Terraform sends identical to what the API reports. Minimum 1m."

  validation {
    condition     = can(regex("^[1-9][0-9]*(m|h)$", var.default_posture_schedule))
    error_message = "default_posture_schedule must be a whole number of minutes or hours in one unit, such as \"5m\"."
  }
}

variable "default_integration_interval" {
  type        = string
  default     = "10m"
  description = "How often Cloudflare polls a service provider integration that names no interval of its own. Shorter revokes a device the MDM or EDR has marked non-compliant sooner, at the cost of more calls against the provider's API rate limit."

  validation {
    condition     = can(regex("^[1-9][0-9]*(m|h)$", var.default_integration_interval))
    error_message = "default_integration_interval must be a whole number of minutes or hours in one unit, such as \"10m\" or \"1h\"."
  }
}

variable "derive_posture_expiration" {
  type        = bool
  default     = true
  description = <<-EOT
    Give a rule that names no expiration one of twice its polling period - the
    schedule for a device check, the integration's interval for a service
    provider check. Twice is Cloudflare's own recommendation.

    Without an expiration, a result stands until the device reports again. A
    laptop that stops reporting - WARP switched off, the machine offline, the
    agent removed - keeps its last pass indefinitely, and the policy requiring
    that pass keeps admitting it.

    A rule reading through an integration managed elsewhere (integration_id)
    has no interval this layer can see, so it gets no derived expiration. Set
    one on the rule.
  EOT
}

# Guardrails
variable "require_signed_binary_checks" {
  type        = bool
  default     = true
  description = <<-EOT
    Fail the plan for a file, application, sentinelone or carbonblack check with
    no signing certificate thumbprint.

    Without one the check passes for any binary at that path. A user who can
    write there - or anything running as them - satisfies "the EDR agent is
    running" with an empty executable of the right name. The thumbprint pins it
    to the vendor's signature and, unlike sha256, survives the vendor's updates.
    Cloudflare suggests testing a new check without it first; turn this off for
    that, on a pull request that says so, and back on afterwards.
  EOT
}

variable "restricted_posture_rule_types" {
  type        = list(string)
  default     = ["tanium"]
  description = <<-EOT
    Posture rule types this layer refuses. The plan fails naming the rule.

    "tanium" is the legacy Access-only Tanium check. Gateway cannot evaluate it,
    and Cloudflare recommends tanium_s2s for any new deployment. Emptying the
    list disables the check.
  EOT
}
