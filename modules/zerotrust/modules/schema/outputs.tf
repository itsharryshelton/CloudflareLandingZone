output "access_groups" {
  description = "var.access_groups, typed and validated. The rule sets are empty objects here; read them from the rule_sets output."
  value       = var.access_groups
}

output "access_policies" {
  description = "var.access_policies, typed, defaulted and validated. The rule sets are not carried here; read them from the rule_sets output."
  value       = var.access_policies
}

output "rule_sets" {
  description = "var.rule_sets, with every attribute present and defaulted."
  value       = var.rule_sets
}
