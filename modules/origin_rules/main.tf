# Zone-level entry-point ruleset for origin selection. Mapping is in locals.tf.
#
# One entry-point ruleset per phase per zone, so this module owns
# http_request_origin for the zone: anything configured in the dashboard for this
# phase is replaced on the first apply.
resource "cloudflare_ruleset" "this" {
  count = length(local.rules) > 0 ? 1 : 0

  zone_id     = var.zone_id
  name        = var.ruleset_name
  kind        = "zone"
  phase       = "http_request_origin"
  description = "Managed by Terraform (cloudflarelandingzone/modules/origin_rules)."

  rules = local.rules

  lifecycle {
    precondition {
      condition     = length(distinct(local.rule_labels)) == length(local.rule_labels)
      error_message = "Origin rules must be uniquely labelled: two rules resolve to the same description, which makes them indistinguishable in the Cloudflare dashboard and in audit logs."
    }

    precondition {
      condition     = length(local.sni_without_origin) == 0
      error_message = "These origin rules override sni without overriding origin: ${join(", ", local.sni_without_origin)}. That changes the TLS handshake to the origin DNS already selected, whose certificate presumably matched - which usually means the origin override was forgotten. Set origin.host, or drop the sni override."
    }
  }
}
