variable "account_id" {
  type        = string
  description = "Cloudflare Account ID. Notification policies and webhook destinations are account-scoped: a policy about a zone names that zone in its filters, it is not attached to it."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "webhooks" {
  description = <<-EOT
    Webhook destinations, keyed by a logical key. A policy names one by that key
    in `webhook_keys`. The key is also the state address, so renaming one
    destroys and recreates the destination under a new ID.

    - `name` - Label shown in the dashboard, and sent in the body of every
               notification dispatched to it. Must be unique within this module.

    The URL and the optional secret are not here: they arrive in
    var.webhook_urls and var.webhook_secrets, which are sensitive, because a
    Slack, Discord, Google Chat or Feishu webhook URL is itself the credential.

    Cloudflare decides the destination type (slack, discord, gchat, datadog,
    opsgenie, splunk, feishu or generic) from the URL. The `webhooks` output
    shows what it decided; a URL meant for Slack that comes back "generic" is
    receiving JSON Slack will not render.
  EOT

  type = map(object({
    name = string
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.webhooks) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "webhooks keys must be lowercase alphanumeric with underscores. The key is a state address - renaming one recreates the destination with a new ID."
  }

  validation {
    condition     = alltrue([for w in var.webhooks : trimspace(w.name) != ""])
    error_message = "webhooks[*].name must not be empty. Cloudflare sends it in every notification body, and it is how the dashboard tells destinations apart."
  }
}

variable "webhook_urls" {
  type        = map(string)
  default     = {}
  sensitive   = true
  description = "Key of var.webhooks => the POST endpoint Cloudflare dispatches to. Every webhook needs exactly one. Sensitive because a chat webhook URL carries its own credential; it is still written to state and the saved plan in plain text, because Terraform records what it sent. Generic endpoints must be publicly resolvable on port 80 or 443."
}

variable "webhook_secrets" {
  type        = map(string)
  default     = {}
  sensitive   = true
  description = "Key of var.webhooks => the value Cloudflare sends in the cf-webhook-auth header, so a generic receiver can tell a real notification from a forged one. Optional per webhook. Cloudflare never returns it, so changing it here is the only way to rotate it, and the value is in state in plain text."
}

variable "policies" {
  description = <<-EOT
    Notification policies, keyed by a logical key. One policy is one alert type
    sent to one set of destinations. The key is the state address: renaming one
    destroys and recreates the policy.

    - `name`             - Dashboard label. Must be unique within this module.
    - `alert_type`       - The event that triggers a dispatch, as the API names it
                           (e.g. universal_ssl_event_type, incident_alert,
                           http_alert_origin_error). See the validation below for
                           the full list provider 5.23 accepts. Many are plan- or
                           product-gated; Cloudflare refuses those at apply.
    - `description`      - (Optional) Free text.
    - `enabled`          - (Optional, default true) A disabled policy keeps its
                           configuration and sends nothing.
    - `alert_interval`   - (Optional) How often to re-alert on the same incident,
                           as a duration such as "30m" or "1h". Only some alert
                           types take it.
    - `filters`          - (Optional) Filter name => list of values, narrowing the
                           policy to a subset of events. Which filters an alert type
                           accepts is per type; see Cloudflare's alert type
                           documentation. `zones` takes zone IDs.
    - `email_recipients` - (Optional) Email addresses. Normalised to lower case.
    - `webhook_keys`     - (Optional) Keys of var.webhooks in this module.
    - `webhook_ids`      - (Optional) IDs of webhook destinations managed outside
                           this module.
    - `pagerduty_ids`    - (Optional) IDs of PagerDuty services. PagerDuty is
                           connected in the dashboard, not through Terraform, and
                           each service it exposes has an ID there.

    A policy must reach at least one destination.
  EOT

  type = map(object({
    name             = string
    alert_type       = string
    description      = optional(string)
    enabled          = optional(bool, true)
    alert_interval   = optional(string)
    filters          = optional(map(list(string)), {})
    email_recipients = optional(list(string), [])
    webhook_keys     = optional(list(string), [])
    webhook_ids      = optional(list(string), [])
    pagerduty_ids    = optional(list(string), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.policies) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "policies keys must be lowercase alphanumeric with underscores. The key is a state address - renaming one recreates the policy."
  }

  validation {
    condition     = alltrue([for p in var.policies : trimspace(p.name) != ""])
    error_message = "policies[*].name must not be empty."
  }

  # The list is the provider's own (5.23.0). Validation cannot read a local, so
  # it is written out here; extend it when a provider bump adds an alert type.
  validation {
    condition = alltrue([for p in var.policies : contains([
      "abuse_report_alert", "access_custom_certificate_expiration_type",
      "advanced_ddos_attack_l4_alert", "advanced_ddos_attack_l7_alert",
      "advanced_http_alert_error", "bgp_hijack_notification", "billing_usage_alert",
      "block_notification_block_removed", "block_notification_new_block",
      "block_notification_review_rejected", "bot_traffic_basic_alert",
      "brand_protection_alert", "brand_protection_digest", "clickhouse_alert_fw_anomaly",
      "clickhouse_alert_fw_ent_anomaly", "cloudforce_one_request_notification",
      "cni_maintenance_notification", "custom_analytics", "custom_bot_detection_alert",
      "custom_ssl_certificate_event_type", "dedicated_ssl_certificate_event_type",
      "device_connectivity_anomaly_alert", "dos_attack_l4", "dos_attack_l7",
      "expiring_service_token_alert", "failing_logpush_job_disabled_alert",
      "fbm_auto_advertisement", "fbm_dosd_attack", "fbm_volumetric_attack",
      "health_check_status_notification", "hostname_aop_custom_certificate_expiration_type",
      "http_alert_edge_error", "http_alert_origin_error", "image_notification",
      "image_resizing_notification", "incident_alert", "load_balancing_health_alert",
      "load_balancing_pool_enablement_alert", "logo_match_alert",
      "magic_tunnel_health_check_event", "magic_wan_tunnel_health",
      "maintenance_event_notification", "mtls_certificate_store_certificate_expiration_type",
      "pages_event_alert", "radar_notification", "real_origin_monitoring",
      "scriptmonitor_alert_new_code_change_detections", "scriptmonitor_alert_new_hosts",
      "scriptmonitor_alert_new_malicious_hosts", "scriptmonitor_alert_new_malicious_scripts",
      "scriptmonitor_alert_new_malicious_url", "scriptmonitor_alert_new_max_length_resource_url",
      "scriptmonitor_alert_new_resources", "secondary_dns_all_primaries_failing",
      "secondary_dns_primaries_failing", "secondary_dns_warning",
      "secondary_dns_zone_successfully_updated", "secondary_dns_zone_validation_warning",
      "security_insights_alert", "sentinel_alert", "stream_live_notifications",
      "synthetic_test_latency_alert", "synthetic_test_low_availability_alert",
      "traffic_anomalies_alert", "tunnel_health_event", "tunnel_update_event",
      "universal_ssl_event_type", "web_analytics_metrics_update",
      "zone_aop_custom_certificate_expiration_type",
    ], p.alert_type)])
    error_message = "policies[*].alert_type is not an alert type provider 5.23 accepts. Check the spelling against GET /accounts/<account_id>/alerting/v3/available_alerts. If Cloudflare has added one and the provider accepts it, extend the list in this validation."
  }

  # Also the provider's own list. A filter name outside it is not an error the
  # API reports clearly, so it is caught here.
  validation {
    condition = alltrue(flatten([for p in var.policies : [for name in keys(p.filters) : contains([
      "actions", "affected_asns", "affected_components", "affected_locations", "airport_code",
      "alert_trigger_preferences", "alert_trigger_preferences_value", "enabled", "environment",
      "event", "event_source", "event_type", "group_by", "health_check_id", "incident_impact",
      "input_id", "insight_class", "limit", "logo_tag", "megabits_per_second", "new_health",
      "new_status", "packets_per_second", "pool_id", "pop_names", "product", "project_id",
      "protocol", "query_tag", "requests_per_second", "selectors", "services", "slo", "status",
      "target_hostname", "target_ip", "target_zone_name", "traffic_exclusions", "tunnel_id",
      "tunnel_name", "type", "where", "zones",
    ], name)]]))
    error_message = "policies[*].filters has a filter name provider 5.23 does not accept. Filter names are fixed by the API (zones, pool_id, health_check_id, tunnel_id, ...); see the cloudflare_notification_policy filters block."
  }

  validation {
    condition     = alltrue(flatten([for p in var.policies : [for values in values(p.filters) : length(values) > 0]]))
    error_message = "policies[*].filters entries must list at least one value. An empty filter matches nothing on some alert types and everything on others; leave the filter out instead."
  }

  validation {
    condition     = alltrue([for p in var.policies : p.alert_interval == null || can(regex("^([0-9]+h)?([0-9]+m)?([0-9]+s)?$", coalesce(p.alert_interval, "x"))) && coalesce(p.alert_interval, "x") != ""])
    error_message = "policies[*].alert_interval must be a duration such as \"30m\", \"1h\" or \"1h30m\"."
  }

  validation {
    condition     = alltrue(flatten([for p in var.policies : [for e in p.email_recipients : can(regex("^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$", trimspace(e)))]]))
    error_message = "policies[*].email_recipients must be email addresses (name@example.com). Cloudflare sends to whatever it is given, so a typo is an alert that goes nowhere."
  }
}
