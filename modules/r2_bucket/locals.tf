# Turns the operator-facing schema into the shapes the R2 API wants, and derives
# the values main.tf's preconditions assert on.

locals {
  # Every sub-resource has to name the same jurisdiction as the bucket, or it
  # addresses a bucket of that name in the default jurisdiction instead.
  jurisdiction = var.jurisdiction

  # CORS
  # The operator writes allowed_* flat; the API nests them under `allowed`.
  # Methods are upper-cased because the API is case-sensitive and "get" is the
  # sort of thing that comes back as an unhelpful 400.
  cors_rules = [
    for rule in var.cors_rules : {
      id = rule.id
      allowed = {
        origins = rule.allowed_origins
        methods = [for method in rule.allowed_methods : upper(method)]
        headers = rule.allowed_headers
      }
      expose_headers  = rule.expose_headers
      max_age_seconds = rule.max_age_seconds
    }
  ]

  cors_rule_ids = [for rule in var.cors_rules : rule.id if rule.id != null]

  # Object lifecycle
  # Days in, seconds out: the R2 API measures every age in seconds, and a rule
  # that should have fired after 30 days but was written as `max_age = 30` would
  # delete objects half a minute old.
  lifecycle_rules = [
    for rule in var.lifecycle_rules : {
      id      = rule.id
      enabled = rule.enabled

      # `conditions` is the rule-wide scope; the per-transition `condition`
      # blocks below are what actually fires. Same word, different objects.
      conditions = { prefix = rule.prefix }

      abort_multipart_uploads_transition = rule.abort_multipart_uploads_after_days == null ? null : {
        condition = {
          type    = "Age"
          max_age = rule.abort_multipart_uploads_after_days * 86400
        }
      }

      delete_objects_transition = (
        rule.delete_objects_after_days == null && rule.delete_objects_on_date == null ? null : {
          condition = {
            type    = rule.delete_objects_on_date != null ? "Date" : "Age"
            date    = rule.delete_objects_on_date
            max_age = rule.delete_objects_after_days == null ? null : rule.delete_objects_after_days * 86400
          }
        }
      )

      # A list in the API because S3 has several classes to walk through. R2 has
      # exactly one destination, so this is always a single-element list.
      storage_class_transitions = (
        rule.transition_to_infrequent_access_after_days == null && rule.transition_to_infrequent_access_on_date == null ? null : [{
          storage_class = "InfrequentAccess"
          condition = {
            type    = rule.transition_to_infrequent_access_on_date != null ? "Date" : "Age"
            date    = rule.transition_to_infrequent_access_on_date
            max_age = rule.transition_to_infrequent_access_after_days == null ? null : rule.transition_to_infrequent_access_after_days * 86400
          }
        }]
      )
    }
  ]

  lifecycle_rule_ids = [for rule in var.lifecycle_rules : rule.id]

  # Object lock
  lock_rules = [
    for rule in var.lock_rules : {
      id      = rule.id
      enabled = rule.enabled
      prefix  = rule.prefix
      condition = {
        type            = rule.retain_indefinitely ? "Indefinite" : (rule.retain_until_date != null ? "Date" : "Age")
        date            = rule.retain_until_date
        max_age_seconds = rule.retain_for_days == null ? null : rule.retain_for_days * 86400
      }
    }
  ]

  lock_rule_ids = [for rule in var.lock_rules : rule.id]

  # Custom domains, keyed by hostname so reordering the list never proposes a replacement
  custom_domains = { for domain in var.custom_domains : lower(domain.domain) => domain }

  custom_domain_names = [for domain in var.custom_domains : lower(domain.domain)]

  # Guardrail inputs
  locked_prefixes = [for rule in var.lock_rules : rule.prefix if rule.enabled]

  deleting_lifecycle_rules = [
    for rule in var.lifecycle_rules : rule
    if rule.enabled && (rule.delete_objects_after_days != null || rule.delete_objects_on_date != null)
  ]

  lifecycle_deletions_over_locked_objects = distinct(flatten([
    for rule in local.deleting_lifecycle_rules : [
      for locked in local.locked_prefixes :
      "lifecycle_rules.${rule.id} (prefix \"${rule.prefix}\") overlaps lock_rules prefix \"${locked}\""
      if startswith(rule.prefix, locked) || startswith(locked, rule.prefix)
    ]
  ]))

  redundant_storage_class_transitions = [
    for rule in var.lifecycle_rules : "lifecycle_rules.${rule.id}"
    if var.storage_class == "InfrequentAccess"
    && (rule.transition_to_infrequent_access_after_days != null || rule.transition_to_infrequent_access_on_date != null)
  ]
}
