# Account: account_a - Cloudflare Notifications. Consumed by the notifications layer only.
#
#   terraform -chdir=layers/notifications plan \
#     -var-file=../../accounts/account_a/account.tfvars \
#     -var-file=../../accounts/account_a/zones.tfvars \
#     -var-file=../../accounts/account_a/notifications.tfvars
#
# NO CREDENTIAL GOES IN THIS FILE. A Slack, Discord, Google Chat, Feishu or Teams
# webhook URL is the credential for that channel: leave `url` out here and set
# the whole URL in the TF_VAR_NOTIFICATION_WEBHOOK_SECRETS secret of the
# account_a-plan environment, under the same key. The same secret carries any
# cf-webhook-auth value. The plan refuses a credential-shaped URL in this file.
#
# zone_keys are keys from zones.tfvars, resolved to zone IDs at plan time. Never
# put a zone ID in `filters`.
#
# Before the first apply, check for policies created in the dashboard - see
# layers/notifications/imports.tf - or every alert they cover arrives twice.
#
# The keys are state addresses. Renaming one destroys and recreates the policy
# or webhook.

notification_webhooks = {
  # A generic receiver whose URL carries no credential, so the URL can live
  # here. Cloudflare proves itself to it with cf-webhook-auth, supplied as
  # TF_VAR_NOTIFICATION_WEBHOOK_SECRETS = {"ops_receiver":{"secret":"<random>"}}.
  ops_receiver = {
    name = "Ops alert receiver"
    url  = "https://alerts.example.com/cloudflare"
  }

  # A Slack channel. The URL is the credential, so it is not here: uncomment
  # once TF_VAR_NOTIFICATION_WEBHOOK_SECRETS carries
  # {"noc_slack":{"url":"https://hooks.slack.com/services/..."}}.
  # noc_slack = {
  #   name = "NOC Slack"
  # }
}

notification_policies = {
  # Cloudflare's own incidents, account-wide. Available on every plan.
  cloudflare_incidents = {
    name             = "Cloudflare incidents (major and critical)"
    alert_type       = "incident_alert"
    email_recipients = ["noc@example.com"]
    filters = {
      incident_impact = ["INCIDENT_IMPACT_MAJOR", "INCIDENT_IMPACT_CRITICAL"]
    }
  }

  # Certificate issuance and renewal problems on the zones that serve traffic.
  # A Universal SSL failure is an outage that starts weeks before anyone notices.
  universal_ssl = {
    name             = "Universal SSL events"
    alert_type       = "universal_ssl_event_type"
    zone_keys        = ["primary", "test_domain"]
    email_recipients = ["noc@example.com"]
    webhook_keys     = ["ops_receiver"]
  }

  # HTTP DDoS attacks mitigated on the primary zone. Available on every plan.
  http_ddos_primary = {
    name         = "HTTP DDoS attack (example.com)"
    alert_type   = "dos_attack_l7"
    zone_keys    = ["primary"]
    webhook_keys = ["ops_receiver"]
  }
}
