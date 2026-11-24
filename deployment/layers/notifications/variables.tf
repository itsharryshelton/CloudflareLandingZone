# Layer notifications - inputs.
#
# Cloudflare Notifications: the policies that decide which events - an expiring
# certificate, an origin error spike, a DDoS attack, a Cloudflare incident - are
# sent where, and the webhook destinations they send to. Account-scoped. A
# policy about a zone names it by zone_key, resolved in zone_lookup.tf.
#
# Config files:
#   accounts/<account>/account.tfvars       - the account ID, shared with every layer
#   accounts/<account>/zones.tfvars         - the zone inventory, for zone_keys
#   accounts/<account>/notifications.tfvars - policies and webhooks
#
# Never from a file - the pipeline supplies this from the <account>-plan
# environment:
#   TF_VAR_notification_webhook_secrets - webhook URLs that carry a credential,
#                                         and cf-webhook-auth secrets

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare Account ID this layer run targets. Policies and webhooks are created against it, and a zone_key is only looked up within it."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "zones" {
  description = <<-EOT
    Zone inventory: logical key => domain name. The same file the zones layer is
    given, so the keys mean the same thing in both.

    This layer does not create zones. It looks up only the zones a policy names
    in zone_keys, to get their IDs (see zone_lookup.tf), which keeps the two
    layers' states independent.

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
    error_message = "zones keys must be lowercase alphanumeric with underscores."
  }
}

variable "notification_webhooks" {
  description = <<-EOT
    Webhook destinations, keyed by a logical key. A policy names one by that key
    in webhook_keys. The key is a state address: renaming one destroys and
    recreates the destination under a new ID.

    - `name` - Dashboard label, also sent in the body of every notification.
               Unique within this file.
    - `url`  - (Optional) The POST endpoint, for a generic receiver whose URL
               carries no credential - https://alerts.example.com/cloudflare.
               Leave it out, and supply it as TF_VAR_notification_webhook_secrets
               under the same key, for anything whose URL is the credential:
               Slack, Discord, Google Chat, Feishu, Microsoft Teams, a URL with
               a token or key in its query string. The plan refuses a
               credential-shaped URL here.

    Cloudflare decides the destination type from the URL. The
    notification_webhooks output shows what it decided.
  EOT

  type = map(object({
    name = string
    url  = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.notification_webhooks) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "notification_webhooks keys must be lowercase alphanumeric with underscores. The key is a state address - renaming one recreates the destination with a new ID."
  }

  validation {
    condition     = alltrue([for w in var.notification_webhooks : w.url == null || can(regex("^https?://", trimspace(coalesce(w.url, "x"))))])
    error_message = "notification_webhooks[*].url must be an http:// or https:// URL."
  }
}

# Secret. Never set from a file - see the header of this file.
variable "notification_webhook_secrets" {
  type = map(object({
    url    = optional(string)
    secret = optional(string)
  }))
  default     = {}
  sensitive   = true
  description = <<-EOT
    Webhook credentials, keyed by the same key as var.notification_webhooks.

    - `url`    - The whole webhook URL, when the URL is the credential. Exactly
                 one of this and notification_webhooks.<key>.url must be set.
    - `secret` - (Optional) Sent by Cloudflare in the cf-webhook-auth header, so
                 a generic receiver can reject a request that did not come from
                 Cloudflare. Chat services ignore it. Cloudflare never returns
                 it, so this is the only record of it.

    THIS VARIABLE IS NEVER SET FROM A FILE. It arrives from the pipeline as
    TF_VAR_notification_webhook_secrets, mapped in _terraform-run.yml from the
    <account>-plan environment's TF_VAR_NOTIFICATION_WEBHOOK_SECRETS secret - the
    plan environment, not the apply one, because apply runs a saved plan file
    and never re-reads TF_VAR_:

      TF_VAR_notification_webhook_secrets={"noc_slack":{"url":"https://hooks.slack.com/services/..."},"siem":{"secret":"<random>"}}

    Both values reach Terraform state and the saved plan in plain text, because
    Terraform records what it sent. Give each webhook its own channel and URL,
    so a leaked one can be revoked without silencing every other alert.
  EOT
}

variable "notification_policies" {
  description = <<-EOT
    Notification policies, keyed by a logical key. One policy is one alert type
    sent to one set of destinations. The key is a state address: renaming one
    destroys and recreates the policy.

    - `name`             - Dashboard label. Unique within this file.
    - `alert_type`       - The event, as the API names it: universal_ssl_event_type,
                           incident_alert, http_alert_origin_error, dos_attack_l7,
                           load_balancing_health_alert, tunnel_health_event and so
                           on. The module validates it against the provider's
                           list. Many are plan- or product-gated, and Cloudflare
                           refuses those at apply, not at plan.
    - `description`      - (Optional) Free text.
    - `enabled`          - (Optional) Falls back to var.default_policy_enabled.
    - `alert_interval`   - (Optional) Re-alert interval for the same incident, such
                           as "30m" or "1h". Only some alert types take it.
    - `zone_keys`        - (Optional) Keys from zones.tfvars. Resolved to zone IDs
                           and sent as the `zones` filter, so the policy fires for
                           those zones only. Leave it out for every zone.
    - `filters`          - (Optional) Any other filter: name => list of values.
                           Which filters an alert type takes is per type - see
                           Cloudflare's alert type documentation. Never `zones`:
                           use zone_keys, so no zone ID is committed.
    - `email_recipients` - (Optional) Email addresses. Checked against
                           var.allowed_email_domains.
    - `webhook_keys`     - (Optional) Keys of var.notification_webhooks.
    - `webhook_ids`      - (Optional) IDs of webhook destinations managed outside
                           this layer.
    - `pagerduty_ids`    - (Optional) PagerDuty service IDs. PagerDuty is connected
                           in the dashboard (Notifications > Destinations), never
                           here; take each service's ID from there.

    A policy must reach at least one destination.
  EOT

  type = map(object({
    name             = string
    alert_type       = string
    description      = optional(string)
    enabled          = optional(bool)
    alert_interval   = optional(string)
    zone_keys        = optional(list(string), [])
    filters          = optional(map(list(string)), {})
    email_recipients = optional(list(string), [])
    webhook_keys     = optional(list(string), [])
    webhook_ids      = optional(list(string), [])
    pagerduty_ids    = optional(list(string), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.notification_policies) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "notification_policies keys must be lowercase alphanumeric with underscores. The key is a state address - renaming one recreates the policy."
  }

  validation {
    condition     = alltrue([for p in var.notification_policies : !contains(keys(p.filters), "zones")])
    error_message = "notification_policies[*].filters must not set `zones`. Name the zones with zone_keys instead, so the layer resolves them by name and no zone ID is committed to an account tree."
  }
}

variable "default_policy_enabled" {
  type        = bool
  description = "Whether a policy that does not state `enabled` is switched on. Set in defaults.auto.tfvars."
}

variable "allowed_email_domains" {
  type        = list(string)
  description = <<-EOT
    Email domains an alert may be sent to, for example ["example.com"]. Matched
    case-insensitively against the part after the "@", so each subdomain needs
    its own entry. Empty allows any domain. Set in defaults.auto.tfvars, or per
    account in notifications.tfvars.

    An alert carries hostnames, origin addresses, attack targets and incident
    detail. Set this wherever alerts should only reach staff of one
    organisation, so a typo or a personal address fails the plan rather than
    quietly receiving them.
  EOT

  validation {
    condition     = alltrue([for domain in var.allowed_email_domains : can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,}$", lower(trimspace(domain))))])
    error_message = "Each allowed_email_domains entry must be a bare domain such as example.com - no \"@\", no scheme, no path."
  }
}

variable "required_alert_types" {
  type        = list(string)
  description = "Alert types every account must have an enabled policy for. Set in defaults.auto.tfvars. Empty requires nothing; a platform that wants, say, certificate expiry alerts on every account lists the types here, and an account without one fails the plan."
}

variable "allow_insecure_webhook_urls" {
  type        = bool
  description = "Whether a webhook may use plain http://. Set in defaults.auto.tfvars. An alert sent over http crosses the internet readable, along with any cf-webhook-auth secret in its headers."
}
