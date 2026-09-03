resource "terraform_data" "preflight" {
  input = {
    rule_policies    = length(var.rule_policies)
    referenced_zones = length(local.referenced_zones)
  }

  lifecycle {
    precondition {
      condition     = length(local.dangling_zone_keys) == 0
      error_message = "zone_key does not match any entry in var.zones: ${join("; ", local.dangling_zone_keys)}. Valid keys: ${join(", ", keys(var.zones))}. Both layers must be given the same accounts/<account>/zones.tfvars."
    }

    precondition {
      condition     = length(local.empty_policies) == 0
      error_message = "These rule_policies entries configure no rules in any phase: ${join(", ", local.empty_policies)}. A policy with nothing in it reads as coverage that does not exist - either give it rules or remove it."
    }

    precondition {
      condition     = length(local.unguarded_cache_rules) == 0
      error_message = "These cache rules set cache = true without excluding authenticated traffic: ${join("; ", local.unguarded_cache_rules)}. cache = true overrides the checks that keep a response carrying a session cookie out of the shared cache, so a page rendered for one signed-in user can be served to the next. Either gate the expression on the session cookie (the usual form is `and not http.cookie contains \"SESS\"`), or set acknowledge_public_response = true on the rule to record that these responses are the same for every visitor."
    }
  }
}
