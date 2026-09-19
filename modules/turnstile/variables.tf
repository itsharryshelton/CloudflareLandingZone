variable "account_id" {
  type        = string
  description = "Cloudflare Account ID. Turnstile widgets are account-scoped: a widget is not attached to a zone, and its hostname list may name domains this account does not hold."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "widgets" {
  description = <<-EOT
    Turnstile widgets, keyed by a logical key. The key is Terraform's handle and
    is what the outputs are keyed by; `name` is only a dashboard label.

    - `name`            - Human-readable label. Cloudflare does not require it to be
                          unique, this module does - two widgets called the same thing
                          are indistinguishable in the dashboard, which is where a
                          sitekey gets looked up when a site breaks.
    - `domains`         - Hostnames the widget is allowed to run on. A hostname covers
                          itself and every subdomain, so "example.com" also serves
                          "www.example.com". Listing "www.example.com" does NOT serve the
                          apex. FQDNs only: no scheme, no port, no path, no wildcards.
    - `mode`            - managed | non-interactive | invisible. See below.
    - `bot_fight_mode`  - (Optional, default false) Enterprise. Serves computationally
                          expensive challenges to clients judged malicious.
    - `clearance_level` - (Optional) Pre-clearance: what WAF challenge the cf_clearance
                          cookie this widget issues will satisfy on the matching zone.
                          no_clearance | jschallenge | managed | interactive.
    - `ephemeral_id`    - (Optional, default false) Enterprise. Returns an ephemeral ID
                          in the /siteverify response, for correlating repeat solvers.
    - `offlabel`        - (Optional, default false) Enterprise. Removes Cloudflare
                          branding from the widget.
    - `region`          - (Optional) world | china. FIXED AT CREATION: changing it
                          replaces the widget and issues a new sitekey.

    THE SITEKEY IS THE THING THAT MATTERS
    A widget is two keys: the sitekey, which is public and embedded in the page,
    and the secret, which the backend sends to /siteverify. Terraform creates the
    widget; it cannot tell the site which sitekey to embed. So a widget replaced
    rather than updated - a `region` change, a destroy and recreate, an apply
    against an empty state - issues a new sitekey, and every page still carrying
    the old one fails every challenge until it is redeployed. Treat a plan that
    says "must be replaced" on a live widget as an outage, not a diff.

    CHOOSING A MODE
    - managed         - Cloudflare decides, and asks for a click only when it needs
                        one. The default, and correct for a login or a signup form.
    - non-interactive - Always shows a spinner, never asks for a click.
    - invisible       - No visible element at all. Nothing tells the visitor a
                        challenge ran, so using it requires Cloudflare's privacy
                        addendum. It is also the mode that fails silently: a broken
                        invisible widget looks like a form that just does not submit.
  EOT

  type = map(object({
    name            = string
    domains         = list(string)
    mode            = string
    bot_fight_mode  = optional(bool, false)
    clearance_level = optional(string)
    ephemeral_id    = optional(bool, false)
    offlabel        = optional(bool, false)
    region          = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.widgets) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "widgets keys must be lowercase alphanumeric with underscores. The key is the handle every output is keyed by."
  }

  validation {
    condition     = alltrue([for w in var.widgets : contains(["managed", "non-interactive", "invisible"], w.mode)])
    error_message = "mode must be one of: managed, non-interactive, invisible."
  }

  validation {
    condition     = alltrue([for w in var.widgets : w.clearance_level == null || contains(["no_clearance", "jschallenge", "managed", "interactive"], coalesce(w.clearance_level, "no_clearance"))])
    error_message = "clearance_level must be one of: no_clearance, jschallenge, managed, interactive."
  }

  validation {
    condition     = alltrue([for w in var.widgets : w.region == null || contains(["world", "china"], coalesce(w.region, "world"))])
    error_message = "region must be world or china, and cannot be changed after creation - a change replaces the widget and issues a new sitekey."
  }

  validation {
    condition     = alltrue([for w in var.widgets : length(w.domains) > 0])
    error_message = "every widget must list at least one hostname. A widget with no hostnames cannot run anywhere."
  }

  validation {
    condition     = alltrue([for w in var.widgets : alltrue([for d in w.domains : can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?([.][a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", lower(trimspace(d))))])])
    error_message = "domains must be fully qualified hostnames: no scheme (https://), no port, no path, no wildcard. A hostname already covers its subdomains, so \"*.example.com\" is both rejected and unnecessary - list \"example.com\"."
  }

  validation {
    condition     = alltrue([for w in var.widgets : trimspace(w.name) != ""])
    error_message = "name must not be empty. It is the only thing identifying the widget in the dashboard when somebody is trying to find which sitekey a failing page uses."
  }
}

variable "max_domains_per_widget" {
  type        = number
  default     = 200
  description = "Ceiling on hostnames in one widget. Cloudflare's own limit is 10 on non-Enterprise plans and 200 on Enterprise; exceeding it is rejected at apply, after the plan was approved."

  validation {
    condition     = var.max_domains_per_widget > 0 && var.max_domains_per_widget <= 200
    error_message = "max_domains_per_widget must be between 1 and 200 - 200 is Cloudflare's Enterprise ceiling."
  }
}
