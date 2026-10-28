# Zone-level entry-point ruleset for Configuration Rules: zone settings
# overridden per request. Mapping is in locals.tf.
#
# One entry-point ruleset per phase per zone, so this module owns
# http_config_settings for the zone: anything configured in the dashboard for
# this phase is replaced on the first apply.
resource "cloudflare_ruleset" "this" {
  count = length(local.rules) > 0 ? 1 : 0

  zone_id     = var.zone_id
  name        = var.ruleset_name
  kind        = "zone"
  phase       = "http_config_settings"
  description = "Managed by Terraform (cloudflarelandingzone/modules/config_rules)."

  rules = local.rules

  lifecycle {
    precondition {
      condition     = length(distinct(local.rule_labels)) == length(local.rule_labels)
      error_message = "Configuration rules must be uniquely labelled: two rules resolve to the same description, which makes them indistinguishable in the Cloudflare dashboard and in audit logs."
    }
  }
}
