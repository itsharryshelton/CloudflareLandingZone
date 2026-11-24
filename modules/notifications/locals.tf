locals {
  # Only the keys of the sensitive maps are read here, never a value, so nothing
  # sensitive reaches a for_each or a precondition message.
  webhook_url_keys    = nonsensitive(keys(var.webhook_urls))
  webhook_secret_keys = nonsensitive(keys(var.webhook_secrets))

  webhooks = {
    for key, webhook in var.webhooks : key => {
      name = trimspace(webhook.name)
    }
  }

  # Normalised to what the API stores, so the plan after the first apply is
  # empty. Mechanism IDs are sets at Cloudflare, so order and duplicates in the
  # input carry no meaning.
  policies = {
    for key, policy in var.policies : key => merge(policy, {
      name             = trimspace(policy.name)
      email_recipients = sort(distinct([for e in policy.email_recipients : lower(trimspace(e))]))
      webhook_keys     = sort(distinct(policy.webhook_keys))
      webhook_ids      = sort(distinct([for id in policy.webhook_ids : trimspace(id)]))
      pagerduty_ids    = sort(distinct([for id in policy.pagerduty_ids : trimspace(id)]))

      # Only the filters that were set. The provider's filters object has every
      # filter as an optional attribute, so the rest arrive as null; null for
      # the whole block when nothing was set, which is what the API returns.
      filters = length(policy.filters) == 0 ? null : {
        for name, values in policy.filters : name => distinct([for v in values : trimspace(v)])
      }
    })
  }

  # Derived assertions, consumed by the preconditions in main.tf.

  # Cloudflare permits two policies, or two webhooks, with the same name. The
  # dashboard then lists both, and nothing in it says which one this module owns.
  duplicate_policy_names = sort([
    for name, claimants in {
      for key, policy in local.policies : lower(policy.name) => key...
    } : "\"${name}\" (${join(", ", sort(claimants))})" if length(claimants) > 1
  ])

  duplicate_webhook_names = sort([
    for name, claimants in {
      for key, webhook in local.webhooks : lower(webhook.name) => key...
    } : "\"${name}\" (${join(", ", sort(claimants))})" if length(claimants) > 1
  ])

  unknown_webhook_keys = sort(flatten([
    for key, policy in local.policies : [
      for webhook_key in policy.webhook_keys : "policies.${key} -> \"${webhook_key}\""
      if !contains(keys(var.webhooks), webhook_key)
    ]
  ]))

  # A policy with no destination is accepted by the API and alerts nobody.
  policies_without_destination = sort([
    for key, policy in local.policies : "policies.${key}"
    if length(policy.email_recipients) + length(policy.webhook_keys) + length(policy.webhook_ids) + length(policy.pagerduty_ids) == 0
  ])

  webhooks_without_url = sort([
    for key in keys(var.webhooks) : key if !contains(local.webhook_url_keys, key)
  ])

  orphaned_webhook_urls = sort([
    for key in local.webhook_url_keys : key if !contains(keys(var.webhooks), key)
  ])

  orphaned_webhook_secrets = sort([
    for key in local.webhook_secret_keys : key if !contains(keys(var.webhooks), key)
  ])
}
