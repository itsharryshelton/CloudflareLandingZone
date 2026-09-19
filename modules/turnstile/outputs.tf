output "widgets" {
  description = "Per-widget identity and posture, keyed by the logical key. Everything here is public: the sitekey is embedded in the page it protects. `deployed_via` and `last_modified_via` are Cloudflare's own record of what last touched the widget - anything but \"api\" means somebody changed it outside this pipeline."
  value = {
    for key, widget in cloudflare_turnstile_widget.this : key => {
      id                = widget.id
      sitekey           = widget.sitekey
      name              = widget.name
      mode              = widget.mode
      domains           = widget.domains
      region            = widget.region
      clearance_level   = widget.clearance_level
      offlabel          = widget.offlabel
      bot_fight_mode    = widget.bot_fight_mode
      ephemeral_id      = widget.ephemeral_id
      created_on        = widget.created_on
      modified_on       = widget.modified_on
      deployed_via      = widget.deployed_via
      last_modified_via = widget.last_modified_via
    }
  }
}

output "sitekeys" {
  description = "Logical key => sitekey. This is the value the page embeds, and the only thing that connects a live form to a widget here. Not sensitive: it is served to every visitor."
  value       = { for key, widget in cloudflare_turnstile_widget.this : key => widget.sitekey }
}

output "secrets" {
  description = "Logical key => secret key, for the backend's /siteverify call. Marked sensitive so it is redacted from plan and apply logs, but it is still in state in plain text, and `terraform output -json` prints it. The only way to rotate one is to recreate the widget, which changes the sitekey too."
  value       = { for key, widget in cloudflare_turnstile_widget.this : key => widget.secret }
  sensitive   = true
}

output "domain_coverage" {
  description = "Hostname => the widget that covers it, one entry per declared hostname. Subdomains are not expanded: an entry for \"example.com\" also serves \"www.example.com\". Use it to answer \"which sitekey should this page be embedding\" without opening the dashboard."
  value       = { for domain, claimants in local.domain_claims : domain => claimants[0] }
}
