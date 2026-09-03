# Zone-level entry-point ruleset for request header rewrites. Mapping is in
# locals.tf.
#
# One entry-point ruleset per phase per zone, so this module owns
# http_request_late_transform for the zone: anything configured in the dashboard
# for this phase is replaced on the first apply.
resource "cloudflare_ruleset" "this" {
  count = length(local.rules) > 0 ? 1 : 0

  zone_id     = var.zone_id
  name        = var.ruleset_name
  kind        = "zone"
  phase       = "http_request_late_transform"
  description = "Managed by Terraform (cloudflarelandingzone/modules/transform_rules)."

  rules = local.rules

  lifecycle {
    precondition {
      condition     = length(distinct(local.rule_labels)) == length(local.rule_labels)
      error_message = "Transform rules must be uniquely labelled: two rules resolve to the same description, which makes them indistinguishable in the Cloudflare dashboard and in audit logs."
    }
  }
}
