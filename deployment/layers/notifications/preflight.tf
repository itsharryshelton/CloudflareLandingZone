resource "terraform_data" "preflight" {
  input = {
    notification_policies = length(var.notification_policies)
    notification_webhooks = length(var.notification_webhooks)
    referenced_zones      = length(local.referenced_zones)
  }

  lifecycle {
    precondition {
      condition     = length(local.dangling_zone_keys) == 0
      error_message = "zone_keys names a zone that is not in var.zones: ${join("; ", local.dangling_zone_keys)}. Valid keys: ${join(", ", sort(keys(var.zones)))}. Both layers must be given the same accounts/<account>/zones.tfvars."
    }

    precondition {
      condition     = length(local.committed_credentials) == 0
      error_message = "These webhooks commit a credential-shaped URL in notifications.tfvars: ${join("; ", local.committed_credentials)}. The value is not shown. A Slack, Discord, Google Chat, Feishu or Teams webhook URL, or a URL with a token or key in it, is the credential for that destination. Remove url from notifications.tfvars, supply it as TF_VAR_notification_webhook_secrets under the same key, and revoke the URL at the chat service - it is in git history now, not just in this commit."
    }

    precondition {
      condition     = length(local.webhooks_without_url) == 0
      error_message = "These webhooks have no URL: ${join("; ", local.webhooks_without_url)}. Give url in notifications.tfvars for a generic receiver whose URL carries no credential, or supply it as TF_VAR_notification_webhook_secrets under the same key - from the <account>-plan environment, which runs the plan that reads it."
    }

    precondition {
      condition     = length(local.webhooks_with_two_urls) == 0
      error_message = "These webhooks have a url in notifications.tfvars and another in notification_webhook_secrets: ${join("; ", local.webhooks_with_two_urls)}. One would silently win. Keep a URL that is a credential in the secret only, and one that is not in the file only."
    }

    precondition {
      condition     = length(local.orphaned_webhook_secrets) == 0
      error_message = "notification_webhook_secrets holds entries for keys that are not in var.notification_webhooks: ${join(", ", local.orphaned_webhook_secrets)}. Either the webhook was removed and its credential was not, or the key is misspelled and the webhook it was meant for is missing it. Revoke the URL at the chat service and remove it from the environment."
    }

    precondition {
      condition     = length(local.insecure_webhooks) == 0
      error_message = "These webhooks dispatch over plain http://: ${join("; ", local.insecure_webhooks)}. An alert carries hostnames, origin addresses and incident detail, and the cf-webhook-auth secret rides in its headers; over http all of it crosses the internet readable. Use https://, or set allow_insecure_webhook_urls = true in layers/notifications/defaults.auto.tfvars on a pull request that says why."
    }

    precondition {
      condition     = length(local.external_recipients) == 0
      error_message = "These policies email an address outside allowed_email_domains (${join(", ", var.allowed_email_domains)}): ${join("; ", local.external_recipients)}. Alerts carry hostnames, origin addresses and attack detail. Correct the address, or add its domain to allowed_email_domains."
    }

    precondition {
      condition     = length(local.missing_required_alert_types) == 0
      error_message = "This account has no enabled policy for these required alert types: ${join(", ", local.missing_required_alert_types)}. required_alert_types in layers/notifications/defaults.auto.tfvars makes them mandatory for every account. Add a policy for each to accounts/<account>/notifications.tfvars."
    }
  }
}
