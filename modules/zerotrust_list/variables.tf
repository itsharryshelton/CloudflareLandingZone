variable "account_id" {
  type        = string
  description = "Cloudflare Account ID that owns the list. Zero Trust lists are account-scoped and are referenced from Gateway policies by UUID, as `$<id>`."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "name" {
  type        = string
  description = <<-EOT
    Display name of the list in the Zero Trust dashboard (Reusable components >
    Lists) and in the policy builder's "in list" picker.

    Unlike a WAF list, a Gateway policy does not refer to this name - it refers
    to the list's UUID - so renaming is an in-place update that breaks nothing.
  EOT

  validation {
    condition     = trimspace(var.name) != "" && trimspace(var.name) == var.name
    error_message = "name must be non-empty and carry no leading or trailing whitespace. The dashboard trims it, and a name that differs from what Cloudflare stores is drift on every plan."
  }
}

variable "type" {
  type        = string
  description = <<-EOT
    What the list holds. Fixed at creation: changing it replaces the list, and a
    replaced list has a new UUID, so every policy reading it is rewritten in the
    same apply.

      DOMAIN - hostnames. Used by the Domain, Host and SNI selectors
      IP     - IPv4 or IPv6 addresses and CIDR ranges
      URL    - URLs, matched by the HTTP URL selector
      EMAIL  - user email addresses, matched by the identity email selector
      SERIAL - device serial numbers, for device posture
      AAGUID - FIDO authenticator AAGUIDs (UUIDs)
      CATEGORY, LOCATION, DEVICE - newer list types the API accepts; their
               values are passed through without a shape check

    Upper case, as the API spells them.
  EOT

  validation {
    condition     = contains(["SERIAL", "URL", "DOMAIN", "EMAIL", "IP", "CATEGORY", "LOCATION", "DEVICE", "AAGUID"], var.type)
    error_message = "type must be one of SERIAL, URL, DOMAIN, EMAIL, IP, CATEGORY, LOCATION, DEVICE, AAGUID - upper case, as the Cloudflare API spells them."
  }
}

variable "description" {
  type        = string
  default     = null
  description = "Free-text summary shown in the dashboard. Worth spending: a policy shows only the list's name, and \"why is this domain here\" is not a question the entries answer."
}

variable "items" {
  type = list(object({
    value       = string
    description = optional(string)
  }))
  description = <<-EOT
    The entries. Terraform owns them all: Cloudflare stores them as one set and
    an apply writes the whole set, so an entry added in the dashboard is removed
    by the next apply.

      - `value`       : the entry, in the shape `type` demands. DOMAIN and EMAIL
                        values are lower-cased before they are sent. An IP entry
                        must be written the way Cloudflare stores it - a CIDR on
                        its network boundary, IPv6 compressed and lower case - or
                        it would show as drift on every plan, so the plan says
                        which form to use.
      - `description` : (Optional) why this entry is here. Six months later it is
                        the only thing separating a deliberate entry from a
                        forgotten one.

    At least one entry. An empty list is not "nothing to match" to a policy that
    reads it: a block matches nothing while looking like a control, and a
    negated rule matches everything.
  EOT

  validation {
    condition     = length(var.items) > 0
    error_message = "items must contain at least one entry. A policy reading an empty list matches nothing (or, negated, everything) while the dashboard shows it configured."
  }

  validation {
    condition     = alltrue([for item in var.items : trimspace(item.value) != "" && trimspace(item.value) == item.value])
    error_message = "Each items[*].value must be non-empty with no leading or trailing whitespace. Cloudflare trims it on save, which would show as drift on every plan."
  }
}

variable "max_items" {
  type        = number
  default     = 1000
  description = "Ceiling on how many entries this list may hold. Every entry is in state and in every plan, so past this the plan stops being reviewable - and Cloudflare caps entries per list by plan, so a list that outgrows this is usually one that needs a different approach (a category, an application, or a feed) rather than more rows."

  validation {
    condition     = var.max_items >= 1
    error_message = "max_items must be at least 1."
  }
}
