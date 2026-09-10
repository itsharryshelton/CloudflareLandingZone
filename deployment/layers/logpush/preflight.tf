resource "terraform_data" "preflight" {
  input = {
    logpush_jobs     = length(var.logpush_jobs)
    referenced_zones = length(local.referenced_zones)
  }

  lifecycle {
    precondition {
      condition     = length(local.dangling_zone_keys) == 0
      error_message = "zone_key does not match any entry in var.zones: ${join("; ", local.dangling_zone_keys)}. Valid keys: ${join(", ", sort(keys(var.zones)))}. Both layers must be given the same accounts/<account>/zones.tfvars."
    }

    precondition {
      condition     = length(local.unknown_datasets) == 0
      error_message = "These jobs name a dataset in neither var.logpush_zone_datasets nor var.logpush_account_datasets: ${join("; ", local.unknown_datasets)}. Check the spelling against Cloudflare's Logpush dataset list. If Cloudflare has added it and the provider accepts it, add it to the catalogue in layers/logpush/variables.tf."
    }

    precondition {
      condition     = length(local.zone_datasets_without_zone) == 0
      error_message = "These jobs push a zone dataset but name no zone_key: ${join("; ", local.zone_datasets_without_zone)}. Cloudflare produces these per zone and refuses them on an account-scoped job. Add the zone_key from zones.tfvars."
    }

    precondition {
      condition     = length(local.account_datasets_with_zone) == 0
      error_message = "These jobs push an account dataset but name a zone_key: ${join("; ", local.account_datasets_with_zone)}. Cloudflare produces these per account and refuses them on a zone-scoped job. Remove the zone_key."
    }

    precondition {
      condition     = length(local.underpowered_zone_jobs) == 0
      error_message = "These zone-scoped jobs target a zone below logpush_min_zone_tier (\"${var.logpush_min_zone_tier}\"): ${join("; ", local.underpowered_zone_jobs)}. Zone Logpush is an Enterprise entitlement and Cloudflare refuses the job on a lower plan, at apply. Either set the zone's real zone_tier in zones.tfvars, drop the job, or lower logpush_min_zone_tier if your contract genuinely entitles the plan it is on."
    }

    precondition {
      condition     = length(local.committed_credentials) == 0
      error_message = "These jobs commit a credential in destination_conf: ${join("; ", local.committed_credentials)}. The value is not shown. Remove destination_conf from logpush.tfvars, supply the whole URI as TF_VAR_logpush_destination_secrets under the same key, and rotate the credential - it is in git history now, not just in this commit."
    }

    precondition {
      condition     = length(local.jobs_without_destination) == 0
      error_message = "These jobs have no destination: ${join("; ", local.jobs_without_destination)}. Give destination_conf in logpush.tfvars for one with no credential in it, or supply it as TF_VAR_logpush_destination_secrets under the same key - from the <account>-plan environment, which runs the plan that reads it."
    }

    precondition {
      condition     = length(local.jobs_with_two_destinations) == 0
      error_message = "These jobs have a destination_conf in logpush.tfvars and an entry in logpush_destination_secrets: ${join("; ", local.jobs_with_two_destinations)}. One would silently win. Keep a destination with a credential in the secret only, and one without in the file only."
    }

    precondition {
      condition     = length(local.orphaned_destination_secrets) == 0
      error_message = "logpush_destination_secrets holds entries for keys that are not in var.logpush_jobs: ${join(", ", local.orphaned_destination_secrets)}. Either the job was removed and its credential was not, or the key is misspelled and the job it was meant for has no destination. Revoke the credential at the destination and remove it from the environment."
    }

    precondition {
      condition     = length(local.orphaned_ownership_challenges) == 0
      error_message = "logpush_ownership_challenges holds entries for keys that are not in var.logpush_jobs: ${join(", ", local.orphaned_ownership_challenges)}. Either the job was removed or the key is misspelled, and the job it was meant for will be refused by Cloudflare without it."
    }

    precondition {
      condition     = length(local.insecure_destinations) == 0
      error_message = "These jobs push over plain http:// or with insecure-skip-verify=true: ${join("; ", local.insecure_destinations)}. Logs carry client IPs, identities and URLs; unencrypted they cross the internet readable, and unverified they go to whatever answers on that address. Use https:// with a valid certificate, or set allow_insecure_logpush_destinations = true in layers/logpush/defaults.auto.tfvars on a pull request that says why."
    }

    precondition {
      condition     = length(local.sampled_jobs) == 0
      error_message = "These jobs sample their output: ${join("; ", local.sampled_jobs)}. A sampled log drops events at random, and the one that matters in an incident is as likely to go as any other. Remove sample_rate, or set allow_logpush_sampling = true in layers/logpush/defaults.auto.tfvars for a feed that is analytics rather than evidence."
    }

    precondition {
      condition     = length(local.missing_required_datasets) == 0
      error_message = "This account pushes no enabled account-scoped job for these required datasets: ${join(", ", local.missing_required_datasets)}. required_logpush_account_datasets in layers/logpush/defaults.auto.tfvars makes them mandatory for every account. Add a job for each to accounts/<account>/logpush.tfvars."
    }
  }
}
