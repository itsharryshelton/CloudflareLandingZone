output "policies" {
  description = "Per-policy identity, keyed by the logical key: id, name, alert_type and enabled. No destinations: email addresses are personal data, and an output ends up in an apply log."
  value = {
    for key, policy in cloudflare_notification_policy.this : key => {
      id         = policy.id
      name       = policy.name
      alert_type = policy.alert_type
      enabled    = policy.enabled
      created    = policy.created
      modified   = policy.modified
    }
  }
}

output "policy_ids" {
  description = "Logical key => notification policy ID."
  value       = { for key, policy in cloudflare_notification_policy.this : key => policy.id }
}

output "webhooks" {
  description = "Per-webhook identity and health, keyed by the logical key. `type` is what Cloudflare detected from the URL (slack, discord, gchat, generic, ...): a Slack URL reported as \"generic\" is receiving JSON Slack will not render. `last_success` and `last_failure` are Cloudflare's own dispatch record. No URL and no secret - either may be the credential."
  value = {
    for key, webhook in cloudflare_notification_policy_webhooks.this : key => {
      id           = webhook.id
      name         = webhook.name
      type         = webhook.type
      created_at   = webhook.created_at
      last_success = webhook.last_success
      last_failure = webhook.last_failure
    }
  }
}

output "webhook_ids" {
  description = "Logical key => webhook destination ID, for a policy managed outside this module to name in its webhook mechanisms."
  value       = { for key, webhook in cloudflare_notification_policy_webhooks.this : key => webhook.id }
}
