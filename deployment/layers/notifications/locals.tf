# Applies the platform baseline, resolves zone keys and each webhook's URL, and
# derives the preflight assertions, so that notifications.tf reads as a plain
# module call.

locals {
  # Only zones a policy names are looked up, so an account whose policies are
  # all account-wide costs no API call.
  referenced_zone_keys = distinct(flatten([for policy in var.notification_policies : policy.zone_keys]))

  referenced_zones = {
    for key, zone in var.zones : key => zone
    if contains(local.referenced_zone_keys, key)
  }

  # Only keys, and yes/no facts about values, are read from the secret map, so
  # nothing sensitive reaches a for_each key or a precondition message.
  # nonsensitive() is safe on each of these: what it unmarks is a key or a
  # boolean, never a URL or a secret.
  secret_keys = nonsensitive(keys(var.notification_webhook_secrets))

  secret_url_keys = sort([
    for key in local.secret_keys : key if nonsensitive(var.notification_webhook_secrets[key].url != null)
  ])

  secret_secret_keys = sort([
    for key in local.secret_keys : key if nonsensitive(var.notification_webhook_secrets[key].secret != null)
  ])

  file_url_keys = sort([
    for key, webhook in var.notification_webhooks : key if webhook.url != null
  ])

  # Module inputs. Each webhook's URL comes from exactly one of the two places;
  # preflight refuses both or neither.
  webhooks = {
    for key, webhook in var.notification_webhooks : key => { name = webhook.name }
  }

  webhook_urls = merge(
    { for key, webhook in var.notification_webhooks : key => trimspace(webhook.url) if webhook.url != null },
    { for key in local.secret_url_keys : key => trimspace(var.notification_webhook_secrets[key].url) if contains(keys(var.notification_webhooks), key) },
  )

  webhook_secrets = {
    for key in local.secret_secret_keys : key => var.notification_webhook_secrets[key].secret
    if contains(keys(var.notification_webhooks), key)
  }

  # A policy whose zone_keys do not all resolve is left out and reported by
  # preflight, rather than failing on an index with a message that cannot name
  # it. zone_keys becomes the `zones` filter, which takes zone IDs.
  policies = {
    for key, policy in var.notification_policies : key => {
      name             = policy.name
      alert_type       = policy.alert_type
      description      = policy.description
      enabled          = coalesce(policy.enabled, var.default_policy_enabled)
      alert_interval   = policy.alert_interval
      email_recipients = policy.email_recipients
      webhook_keys     = policy.webhook_keys
      webhook_ids      = policy.webhook_ids
      pagerduty_ids    = policy.pagerduty_ids
      filters = merge(policy.filters, length(policy.zone_keys) == 0 ? {} : {
        zones = [for zone_key in policy.zone_keys : data.cloudflare_zone.this[zone_key].id]
      })
    }
    if alltrue([for zone_key in policy.zone_keys : contains(keys(var.zones), zone_key)])
  }

  # Derived assertions, consumed by preflight.tf. Cross-item rules inside the
  # module's own inputs - duplicate names, a webhook_key naming nothing, a
  # policy with no destination - are the module's, so they hold for any
  # consumer of it. What is left here is this platform's policy.

  dangling_zone_keys = sort(flatten([
    for key, policy in var.notification_policies : [
      for zone_key in policy.zone_keys : "notification_policies.${key} -> zone_key = \"${zone_key}\""
      if !contains(keys(var.zones), zone_key)
    ]
  ]))

  webhooks_without_url = sort([
    for key in keys(var.notification_webhooks) : "notification_webhooks.${key}"
    if !contains(local.file_url_keys, key) && !contains(local.secret_url_keys, key)
  ])

  webhooks_with_two_urls = sort([
    for key in local.file_url_keys : "notification_webhooks.${key}" if contains(local.secret_url_keys, key)
  ])

  orphaned_webhook_secrets = sort([
    for key in local.secret_keys : key if !contains(keys(var.notification_webhooks), key)
  ])

  # Hosts whose webhook URL is the credential, and query parameters that carry
  # one: Slack, Discord, Google Chat, Feishu/Lark, Microsoft Teams and Power
  # Automate, plus token=, key=, sig= and the like on any URL, and
  # user:password@ in any URL. Not gated: a committed credential is already
  # leaked by the time anyone reads the plan. Only the key is reported.
  credential_url_pattern = "(?i)(://(hooks\\.slack\\.com|(ptb\\.|canary\\.)?discord(app)?\\.com/api/webhooks|chat\\.googleapis\\.com|open\\.feishu\\.cn|open\\.larksuite\\.com|[a-z0-9.-]*webhook\\.office\\.com|[a-z0-9.-]*\\.logic\\.azure\\.com|[a-z0-9.-]*\\.powerplatform\\.com)|[?&](token|key|secret|sig|signature|api[-_]?key|access[-_]?token|auth|password|code)=|://[^/?#@]+:[^/?#@]+@)"

  committed_credentials = sort([
    for key, webhook in var.notification_webhooks : "notification_webhooks.${key}"
    if webhook.url == null ? false : can(regex(local.credential_url_pattern, trimspace(webhook.url)))
  ])

  # A secret URL is inspected too, and only a yes or no leaves it. sensitive()
  # first because nonsensitive() refuses a value that carries no mark, which a
  # committed URL's result does not.
  insecure_webhooks = var.allow_insecure_webhook_urls ? [] : sort([
    for key in keys(var.notification_webhooks) : "notification_webhooks.${key}"
    if contains(keys(local.webhook_urls), key) ? nonsensitive(sensitive(can(regex("(?i)^http://", local.webhook_urls[key])))) : false
  ])

  normalised_allowed_domains = [for domain in var.allowed_email_domains : lower(trimspace(domain))]

  external_recipients = length(local.normalised_allowed_domains) == 0 ? [] : sort(flatten([
    for key, policy in var.notification_policies : [
      for address in policy.email_recipients : "notification_policies.${key} -> ${lower(trimspace(address))}"
      if !contains(local.normalised_allowed_domains, try(split("@", lower(trimspace(address)))[1], ""))
    ]
  ]))

  missing_required_alert_types = sort([
    for alert_type in var.required_alert_types : alert_type
    if length([
      for policy in var.notification_policies : policy
      if policy.alert_type == alert_type && coalesce(policy.enabled, var.default_policy_enabled)
    ]) == 0
  ])
}
