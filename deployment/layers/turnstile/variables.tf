# Layer turnstile - inputs.
#
# Cloudflare Turnstile widgets: the CAPTCHA replacement embedded in a form, and
# the secret its backend validates the resulting token with. Account-scoped and
# attached to no zone, so this layer holds its own state and reads nothing else.
#
# It creates widgets. It does not embed a sitekey in a page, configure a secret
# in a backend, or know whether either has been done.
#
# Config files:
#   accounts/<account>/account.tfvars   - the account ID, shared with every layer
#   accounts/<account>/turnstile.tfvars - the widgets, consumed only here

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare Account ID this layer run targets. Supplied from accounts/<account>/account.tfvars. Widgets are account-scoped, and a widget's sitekey is only valid for the account that issued it."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "turnstile_widgets" {
  description = <<-EOT
    Turnstile widgets, keyed by a logical key. The key is the handle every output
    is keyed by and what a state address is built from, so renaming one destroys
    and recreates the widget - which issues a new sitekey. Do not rename keys.

    - `name`            - Label shown in the Cloudflare dashboard. Must be unique
                          within this file: the dashboard shows the name and not what
                          embeds the sitekey, so two widgets called the same thing
                          cannot be told apart when one of them breaks.
    - `domains`         - Hostnames the widget may run on. A hostname covers itself
                          and every subdomain, so "example.com" also serves
                          "www.example.com"; listing "www.example.com" does NOT serve
                          the apex. FQDNs only - no scheme, port, path or wildcard.
    - `mode`            - (Optional) managed | non-interactive | invisible. Falls back
                          to var.default_widget_mode.
    - `bot_fight_mode`  - (Optional, default false) Enterprise. Serves deliberately
                          expensive challenges to clients judged malicious.
    - `clearance_level` - (Optional) Pre-clearance. The widget issues a cf_clearance
                          cookie satisfying WAF challenges on the matching zone:
                          no_clearance | jschallenge | managed | interactive. Only
                          meaningful when the hostname is a zone on this account that
                          is proxied through Cloudflare.
    - `ephemeral_id`    - (Optional, default false) Enterprise. Returns an ephemeral ID
                          in the /siteverify response, for spotting a single client
                          solving repeatedly.
    - `offlabel`        - (Optional, default false) Enterprise. Removes Cloudflare
                          branding. Gated by var.allow_offlabel_widgets.
    - `region`          - (Optional) world | china. Falls back to
                          var.default_widget_region. FIXED AT CREATION: changing it
                          replaces the widget and issues a new sitekey.

    A REPLACEMENT IS AN OUTAGE
    Updating a widget in place - hostnames, mode, branding - keeps the sitekey,
    so live pages keep working. Replacing one issues a new sitekey while every
    page still carries the old one, and every challenge on those pages fails
    until they are redeployed. Terraform cannot see that, because it does not
    manage the pages. Read any plan on this layer for "must be replaced" before
    approving it, and treat a widget key rename the same way.
  EOT

  type = map(object({
    name            = string
    domains         = list(string)
    mode            = optional(string)
    bot_fight_mode  = optional(bool, false)
    clearance_level = optional(string)
    ephemeral_id    = optional(bool, false)
    offlabel        = optional(bool, false)
    region          = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.turnstile_widgets) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "turnstile_widgets keys must be lowercase alphanumeric with underscores. The key is a state address - renaming one recreates the widget with a new sitekey."
  }
}

variable "default_widget_mode" {
  type        = string
  description = "Mode for a widget that does not state one. Set in defaults.auto.tfvars."

  validation {
    condition     = contains(["managed", "non-interactive", "invisible"], var.default_widget_mode)
    error_message = "default_widget_mode must be one of: managed, non-interactive, invisible."
  }
}

variable "default_widget_region" {
  type        = string
  description = "Region for a widget that does not state one. Set in defaults.auto.tfvars. Immutable per widget once created."

  validation {
    condition     = contains(["world", "china"], var.default_widget_region)
    error_message = "default_widget_region must be world or china."
  }
}

variable "max_domains_per_widget" {
  type        = number
  description = "Ceiling on hostnames in a single widget, enforced before the API sees it. Set in defaults.auto.tfvars."

  validation {
    condition     = var.max_domains_per_widget > 0 && var.max_domains_per_widget <= 200
    error_message = "max_domains_per_widget must be between 1 and 200 - 200 is Cloudflare's Enterprise ceiling, 10 on every other plan."
  }
}

variable "allow_offlabel_widgets" {
  type        = bool
  description = "Whether a widget may set offlabel = true, removing Cloudflare branding. Set in defaults.auto.tfvars."
}

variable "invisible_mode_privacy_addendum_accepted" {
  type        = bool
  description = "Whether the account has accepted Cloudflare's privacy addendum, which invisible mode requires. Set in defaults.auto.tfvars."
}
