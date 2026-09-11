# No integration config: it carries the provider credentials, and an output
# ends up in a plan log.

output "rule_ids" {
  description = "Device posture rule ID per normalised rule name. This is the value an Access rule's device posture condition and a Gateway policy's passed-posture-check selector take."
  value       = { for key, rule in cloudflare_zero_trust_device_posture_rule.this : key => rule.id }
}

output "rules" {
  description = "Device posture rule ID, name, type and enabled flag per normalised rule name. `enabled` is computed by Cloudflare, and false means the rule is evaluated by nothing - a deprecated input is the usual cause."
  value = {
    for key, rule in cloudflare_zero_trust_device_posture_rule.this : key => {
      id      = rule.id
      name    = rule.name
      type    = rule.type
      enabled = rule.enabled
    }
  }
}

output "integration_ids" {
  description = "Service provider integration ID per normalised integration name. A rule managed outside this module reads through an integration by this ID."
  value       = { for key, integration in cloudflare_zero_trust_device_posture_integration.this : key => integration.id }
}
