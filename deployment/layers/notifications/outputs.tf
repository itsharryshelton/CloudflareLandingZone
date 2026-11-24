output "notification_policies" {
  description = "Per-policy id, name, alert_type and enabled flag, keyed by the logical key. No recipients: email addresses are personal data, and an output ends up in an apply log."
  value       = module.notifications.policies
}

output "notification_webhooks" {
  description = "Per-webhook id, name, detected type and Cloudflare's last_success / last_failure, keyed by the logical key. Read `type` after the first apply: a Slack or Teams URL that Cloudflare detected as \"generic\" is being sent JSON the channel will not render. No URL and no secret - either may be the credential."
  value       = module.notifications.webhooks
}
