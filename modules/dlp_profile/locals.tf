# Entry normalisation and pattern checks.
#
# Entries are keyed by name lower-cased. Grouped with `...` first, so a
# duplicate becomes a precondition message naming it rather than Terraform's
# generic "Duplicate object key" pointing into this file.

locals {
  entries_by_key = {
    for entry in var.entries : lower(trimspace(entry.name)) => entry...
  }

  entries = { for key, group in local.entries_by_key : key => group[0] }

  duplicate_entry_names = sort([
    for key, group in local.entries_by_key : key
    if length(group) > 1
  ])

  # regexall on the empty string is the one call that both compiles the pattern
  # and asks whether it can match nothing at all. A pattern Terraform's RE2
  # cannot compile is very likely one Cloudflare's engine rejects too.
  uncompilable_patterns = sort([
    for entry in var.entries : "${entry.name} (${entry.regex})"
    if !can(regexall(entry.regex, ""))
  ])

  # Matches the empty string, therefore matches every request body.
  empty_matching_patterns = sort([
    for entry in var.entries : "${entry.name} (${entry.regex})"
    if can(regexall(entry.regex, "")) && length(try(regexall(entry.regex, ""), [])) > 0
  ])

  enabled_entry_count = length([for entry in var.entries : entry if entry.enabled])
}
