# One Zero Trust (Gateway) list.
#
# A Gateway policy reads a list as `in $<uuid>`, so the policy holds a pointer
# rather than the entries. Changing an entry here changes what every policy
# reading the list matches, without any of those policies appearing in the plan.
# That is the point of a list, and also the thing to remember when reviewing
# one: the blast radius of a list change is every rule that names it.
#
# Not to be confused with account_list, which manages the account-level lists
# the WAF and Rules products read by name (`$name`). The two share nothing.
resource "cloudflare_zero_trust_list" "this" {
  account_id  = var.account_id
  name        = var.name
  type        = var.type
  description = var.description
  items       = local.normalised

  lifecycle {
    precondition {
      condition = (
        length(local.invalid_ip_items) == 0 &&
        length(local.invalid_domain_items) == 0 &&
        length(local.invalid_email_items) == 0 &&
        length(local.invalid_url_items) == 0 &&
        length(local.invalid_aaguid_items) == 0 &&
        length(local.invalid_serial_items) == 0
      )
      error_message = "These entries are not valid for a ${var.type} list: ${join(", ", concat(local.invalid_ip_items, local.invalid_domain_items, local.invalid_email_items, local.invalid_url_items, local.invalid_aaguid_items, local.invalid_serial_items))}. IP takes an address or CIDR; DOMAIN takes a bare hostname (no scheme, path, port or wildcard - a Domain selector already covers subdomains); EMAIL takes an address; URL takes a URL with no whitespace and no trailing slash, which Gateway ignores and would treat as a duplicate; AAGUID takes a UUID; SERIAL takes a serial with no whitespace. Cloudflare rejects a bad entry only after creating the list, so the list would exist, empty, when the apply failed."
    }

    precondition {
      condition     = length(local.non_canonical_ip_items) == 0
      error_message = "These IP entries are not in the form Cloudflare stores them: ${join(", ", local.non_canonical_ip_items)}. A CIDR must sit on its network boundary and IPv6 must be compressed and lower case; otherwise the stored value never matches the configured one and every plan shows a change."
    }

    precondition {
      condition     = length(local.duplicate_values) == 0
      error_message = "The same entry appears more than once${local.case_insensitive ? " (compared lower-cased)" : ""}: ${join(", ", local.duplicate_values)}. Cloudflare rejects the write, and does so after the list exists."
    }

    precondition {
      condition     = length(var.items) <= var.max_items
      error_message = "This list declares ${length(var.items)} entries, over the max_items ceiling of ${var.max_items}. Every entry is in state and in every plan. Raise the ceiling on a pull request that says why, or match on a category, an application or a smaller list instead."
    }
  }
}
