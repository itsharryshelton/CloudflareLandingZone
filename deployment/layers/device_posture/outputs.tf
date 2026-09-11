output "device_posture_rule_ids" {
  description = "Posture rule ID per logical key. Copy one into device_posture_ids in zerotrust.tfvars, or device_posture_check_ids in gateway.tfvars - neither layer can read this state."
  value = {
    for key, rule in var.device_posture_rules : key => module.device_posture.rule_ids[lower(trimspace(rule.name))]
  }
}

output "device_posture_rules" {
  description = "Posture rule ID, name, type and enabled flag per logical key. `enabled` is Cloudflare's own verdict: false means nothing evaluates the rule."
  value = {
    for key, rule in var.device_posture_rules : key => module.device_posture.rules[lower(trimspace(rule.name))]
  }
}

output "device_posture_integrations" {
  description = "Service provider integration ID per logical key. No config: it carries the provider credential, and an output ends up in a plan log."
  value = {
    for key, integration in var.device_posture_integrations : key => module.device_posture.integration_ids[lower(trimspace(integration.name))]
  }
}
