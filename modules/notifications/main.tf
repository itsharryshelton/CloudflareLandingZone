# Cloudflare Notifications for one account: webhook destinations, and the
# policies that decide which events reach them.
#
# A policy is one alert type sent to a set of destinations - email addresses,
# webhooks, PagerDuty services. Account-scoped: a policy about a zone names the
# zone's ID in its filters rather than being attached to it.
#
# Webhooks are declared here as well, so a policy can name one by key. A webhook
# URL for Slack, Discord, Google Chat or Feishu is itself the credential, so the
# URL arrives sensitive, and both it and the optional cf-webhook-auth secret are
# in state in plain text. PagerDuty is the exception: it is connected through
# the dashboard's OAuth flow, has no resource, and is referenced by ID.
#
# WHAT TERRAFORM CANNOT SEE
# Whether an alert reaches a person. An email to a dead mailbox, a webhook URL
# for a deleted channel and a policy for an alert type the account is not
# entitled to all plan and apply cleanly. The `webhooks` output carries
# Cloudflare's own last_success and last_failure per destination.
resource "cloudflare_notification_policy_webhooks" "this" {
  for_each = local.webhooks

  account_id = var.account_id
  name       = each.value.name
  url        = lookup(var.webhook_urls, each.key, null)
  secret     = lookup(var.webhook_secrets, each.key, null)

  lifecycle {
    precondition {
      condition     = length(local.webhooks_without_url) == 0
      error_message = "These webhooks have no entry in webhook_urls: ${join(", ", local.webhooks_without_url)}. Every destination needs exactly one URL."
    }

    precondition {
      condition     = length(local.orphaned_webhook_urls) == 0 && length(local.orphaned_webhook_secrets) == 0
      error_message = "webhook_urls or webhook_secrets hold entries for keys that are not in var.webhooks: ${join(", ", distinct(concat(local.orphaned_webhook_urls, local.orphaned_webhook_secrets)))}. Either the webhook was removed and its credential was not, or a key is misspelled and the webhook it was meant for is missing it."
    }

    precondition {
      condition     = length(local.duplicate_webhook_names) == 0
      error_message = "Two webhooks share a name: ${join("; ", local.duplicate_webhook_names)}. Cloudflare allows it; this module does not, because the name is what the dashboard and every notification body identify the destination by."
    }
  }
}

resource "cloudflare_notification_policy" "this" {
  for_each = local.policies

  account_id     = var.account_id
  name           = each.value.name
  alert_type     = each.value.alert_type
  description    = each.value.description
  enabled        = each.value.enabled
  alert_interval = each.value.alert_interval
  filters        = each.value.filters

  # Each mechanism is a set of { id }. An empty one is sent as null rather than
  # [], matching what the API returns for a mechanism with no members.
  mechanisms = {
    email = length(each.value.email_recipients) == 0 ? null : [
      for address in each.value.email_recipients : { id = address }
    ]
    webhooks = length(each.value.webhook_keys) + length(each.value.webhook_ids) == 0 ? null : [
      for id in distinct(concat(
        [for key in each.value.webhook_keys : cloudflare_notification_policy_webhooks.this[key].id if contains(keys(cloudflare_notification_policy_webhooks.this), key)],
        each.value.webhook_ids,
      )) : { id = id }
    ]
    pagerduty = length(each.value.pagerduty_ids) == 0 ? null : [
      for id in each.value.pagerduty_ids : { id = id }
    ]
  }

  lifecycle {
    precondition {
      condition     = length(local.unknown_webhook_keys) == 0
      error_message = "webhook_keys names a webhook that is not in var.webhooks: ${join("; ", local.unknown_webhook_keys)}. Declared webhooks: ${length(var.webhooks) == 0 ? "(none)" : join(", ", sort(keys(var.webhooks)))}. Use webhook_ids for a destination managed outside this module."
    }

    precondition {
      condition     = length(local.policies_without_destination) == 0
      error_message = "These policies have no destination: ${join(", ", local.policies_without_destination)}. Cloudflare accepts a policy that notifies nobody, which is an alert that silently goes nowhere. Give each at least one of email_recipients, webhook_keys, webhook_ids or pagerduty_ids, or remove it."
    }

    precondition {
      condition     = length(local.duplicate_policy_names) == 0
      error_message = "Two policies share a name: ${join("; ", local.duplicate_policy_names)}. Cloudflare allows it; this module does not, because the dashboard lists policies by name and the pair cannot be told apart there."
    }
  }
}
