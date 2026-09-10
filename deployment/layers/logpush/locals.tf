# Applies the platform baseline, resolves zone keys and each job's destination,
# and derives the preflight assertions, so that logpush.tf reads as a plain
# module call.

locals {
  # Only zones a zone-scoped job targets are looked up, so an account that
  # pushes only account datasets costs no API call.
  referenced_zone_keys = distinct([for job in var.logpush_jobs : job.zone_key if job.zone_key != null])

  referenced_zones = {
    for key, zone in var.zones : key => zone
    if contains(local.referenced_zone_keys, key)
  }

  tier_rank = {
    free                = 0
    partners_free       = 0
    lite                = 1
    pro                 = 2
    pro_plus            = 2
    partners_pro        = 2
    business            = 3
    partners_business   = 3
    enterprise          = 4
    partners_enterprise = 4
    partners_ent        = 4
  }

  zone_tiers = {
    for key, zone in var.zones : key => coalesce(zone.zone_tier, var.default_zone_tier)
  }

  # Only the keys of the secret maps are read here, never a value, so nothing
  # sensitive reaches a for_each or a precondition message.
  destination_secret_keys  = nonsensitive(keys(var.logpush_destination_secrets))
  ownership_challenge_keys = nonsensitive(keys(var.logpush_ownership_challenges))

  # Each job's destination, from whichever of the two places it came from.
  # Preflight refuses a job with both or neither.
  destination_confs = {
    for key, job in var.logpush_jobs : key => (
      job.destination_conf != null ? trimspace(job.destination_conf) : lookup(var.logpush_destination_secrets, key, null)
    )
  }

  # Module inputs. A job whose zone or destination does not resolve is left out
  # and reported by preflight, rather than failing inside the module with a
  # message that cannot name it.
  logpush_jobs = {
    for key, job in var.logpush_jobs : key => {
      zone_id                     = job.zone_key == null ? null : try(data.cloudflare_zone.this[job.zone_key].id, null)
      name                        = job.name
      dataset                     = job.dataset
      kind                        = job.kind
      enabled                     = coalesce(job.enabled, var.default_logpush_job_enabled)
      filter                      = job.filter
      max_upload_bytes            = job.max_upload_bytes
      max_upload_interval_seconds = job.max_upload_interval_seconds
      max_upload_records          = job.max_upload_records

      # Sent whole every time: Cloudflare replaces output_options on update, so
      # an attribute left out would silently return to Cloudflare's default.
      output_options = merge(job.output_options, {
        output_type      = coalesce(job.output_options.output_type, var.default_logpush_output_type)
        timestamp_format = coalesce(job.output_options.timestamp_format, var.default_logpush_timestamp_format)
        cve_2021_44228   = coalesce(job.output_options.cve_2021_44228, var.default_cve_2021_44228_redaction)
      })
    }
    if(job.zone_key == null ? true : contains(keys(var.zones), job.zone_key))
    && (job.destination_conf != null || contains(local.destination_secret_keys, key))
  }

  # Derived assertions, consumed by preflight.tf

  dangling_zone_keys = sort([
    for key, job in var.logpush_jobs : "logpush_jobs.${key} -> zone_key = \"${job.zone_key}\""
    if job.zone_key == null ? false : !contains(keys(var.zones), job.zone_key)
  ])

  unknown_datasets = sort([
    for key, job in var.logpush_jobs : "logpush_jobs.${key} (\"${job.dataset}\")"
    if !contains(concat(var.logpush_zone_datasets, var.logpush_account_datasets), job.dataset)
  ])

  # Each dataset is produced at one scope, a few at both. Cloudflare refuses one
  # pushed from the wrong scope - at apply, after approval.
  zone_datasets_without_zone = sort([
    for key, job in var.logpush_jobs : "logpush_jobs.${key} (${job.dataset})"
    if job.zone_key == null
    && contains(var.logpush_zone_datasets, job.dataset)
    && !contains(var.logpush_account_datasets, job.dataset)
  ])

  account_datasets_with_zone = sort([
    for key, job in var.logpush_jobs : "logpush_jobs.${key} (${job.dataset}, zone_key = \"${job.zone_key}\")"
    if job.zone_key != null
    && contains(var.logpush_account_datasets, job.dataset)
    && !contains(var.logpush_zone_datasets, job.dataset)
  ])

  underpowered_zone_jobs = sort([
    for key, job in var.logpush_jobs :
    "logpush_jobs.${key} (zone \"${job.zone_key}\", tier \"${local.zone_tiers[job.zone_key]}\")"
    if job.zone_key == null ? false : (
      contains(keys(var.zones), job.zone_key)
      ? local.tier_rank[local.zone_tiers[job.zone_key]] < local.tier_rank[var.logpush_min_zone_tier]
      : false
    )
  ])

  jobs_without_destination = sort([
    for key, job in var.logpush_jobs : "logpush_jobs.${key}"
    if job.destination_conf == null && !contains(local.destination_secret_keys, key)
  ])

  jobs_with_two_destinations = sort([
    for key, job in var.logpush_jobs : "logpush_jobs.${key}"
    if job.destination_conf != null && contains(local.destination_secret_keys, key)
  ])

  orphaned_destination_secrets = sort([
    for key in local.destination_secret_keys : key
    if !contains(keys(var.logpush_jobs), key)
  ])

  orphaned_ownership_challenges = sort([
    for key in local.ownership_challenge_keys : key
    if !contains(keys(var.logpush_jobs), key)
  ])

  # Query parameters that carry a credential in the destination formats
  # Cloudflare documents - R2 keys, an Azure SAS signature, auth headers for
  # Splunk, Datadog, SentinelOne and HTTP endpoints, New Relic's Api-Key - plus
  # a Sumo Logic collector URL, whose path is itself the credential, and
  # user:password@ in any URI.
  credential_pattern = "(?i)([?&](access-key-id|secret-access-key|sig|api-key|apikey|token|password|secret|header_[a-z0-9_-]+)=|^sumo://|://[^/?#@]+:[^/?#@]+@)"

  # Not gated: a committed credential is already leaked by the time anyone reads
  # the plan, and there is no configuration that makes committing one right.
  # Only the key is reported - the value is the secret.
  committed_credentials = sort([
    for key, job in var.logpush_jobs : "logpush_jobs.${key}"
    if job.destination_conf == null ? false : can(regex(local.credential_pattern, job.destination_conf))
  ])

  # Governing defaults. Each of these is a configuration Cloudflare accepts
  # happily, and that quietly weakens what the logs are for.

  insecure_destination_pattern = "(?i)(^http://|[?&]insecure-skip-verify=(true|1)(&|$))"

  # A secret destination is inspected too, and only a yes or no leaves it.
  # sensitive() first because nonsensitive() refuses a value that carries no
  # mark, which a committed destination's result does not.
  insecure_destinations = var.allow_insecure_logpush_destinations ? [] : sort([
    for key in keys(var.logpush_jobs) : "logpush_jobs.${key}"
    if nonsensitive(sensitive(can(regex(local.insecure_destination_pattern, local.destination_confs[key]))))
  ])

  sampled_jobs = var.allow_logpush_sampling ? [] : sort([
    for key, job in var.logpush_jobs : "logpush_jobs.${key} (sample_rate = ${job.output_options.sample_rate})"
    if job.output_options.sample_rate == null ? false : job.output_options.sample_rate < 1
  ])

  missing_required_datasets = sort([
    for dataset in var.required_logpush_account_datasets : dataset
    if length([
      for job in var.logpush_jobs : job
      if job.dataset == dataset && job.zone_key == null && coalesce(job.enabled, var.default_logpush_job_enabled)
    ]) == 0
  ])
}
