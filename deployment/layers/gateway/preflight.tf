resource "terraform_data" "preflight" {
  input = {
    gateway_policies    = length(var.gateway_policies)
    baseline_policies   = length(var.gateway_baseline_policies)
    security_categories = length(var.gateway_security_categories)
    content_categories  = length(var.gateway_blocked_content_categories)
    bypass_applications = length(var.gateway_bypass_applications)
    dlp_profiles        = length(var.gateway_dlp_profile_ids)
  }

  lifecycle {
    # A name Cloudflare does not know resolves to nothing, the selector drops out
    # of the compiled expression, and the rule that is left is broader or
    # narrower than the one somebody wrote. The full list is printed because it
    # is the only place an operator can see it.
    precondition {
      condition     = length(local.unknown_category_names) == 0
      error_message = "A Gateway category name matches nothing in this account's category catalogue: ${join("; ", local.unknown_category_names)}. Valid names: ${join(", ", local.category_names)}."
    }

    # The application catalogue runs to hundreds of entries, so it is counted
    # rather than printed.
    precondition {
      condition     = length(local.unknown_application_names) == 0
      error_message = "A Gateway application name matches nothing in this account's application catalogue: ${join("; ", local.unknown_application_names)}. Cloudflare publishes ${local.application_name_count} applications and app types for this account; the names are the ones shown by the Application selector in the Zero Trust dashboard, and the full list can be read with `terraform console` on this layer as data.cloudflare_zero_trust_gateway_app_types_list.this.result."
    }

    precondition {
      condition     = length(local.unsatisfied_baselines) == 0
      error_message = "A selected baseline policy has nothing to act on: ${join("; ", local.unsatisfied_baselines)}. An empty selector set renders as `in {}`, which Cloudflare rejects as a syntax error, and a rule that matched nothing would sit in the dashboard looking like a control. Populate the variable or remove the baseline from gateway_baseline_policies."
    }

    precondition {
      condition     = length(local.reserved_precedence_violations) == 0
      error_message = "These policies claim a precedence reserved for the platform baseline: ${join("; ", local.reserved_precedence_violations)}. Precedence below ${var.reserved_precedence_ceiling} belongs to layers/gateway/locals.gateway.tf. Gateway evaluates a builder in ascending precedence and stops at the first allow or block that matches, so a rule in front of the baseline is the baseline switched off for whatever it matches."
    }

    precondition {
      condition     = length(local.restricted_actions_used) == 0 && length(local.restricted_baseline_actions_used) == 0
      error_message = "A restricted Gateway action was requested - account tree: ${join("; ", local.restricted_actions_used)}; baseline: ${join("; ", local.restricted_baseline_actions_used)}. Restricted actions are ${join(", ", var.restricted_actions)}, set in layers/gateway/defaults.auto.tfvars. Allowing one means removing it from that list on a pull request that says why."
    }

    # Payload logging writes the matched content - the card number, the
    # identifier, the key - into Gateway's logs, where anybody with log access can
    # read it. Useful while tuning a profile, and not something to leave on.
    precondition {
      condition     = var.allow_dlp_payload_logging || length(local.dlp_payload_logging_used) == 0
      error_message = "These policies turn on DLP payload logging: ${join(", ", local.dlp_payload_logging_used)}. That stores the fragment of the request that triggered the match - which is the sensitive data the policy exists to protect - in Cloudflare's logs, readable by everybody with Gateway log access and retained on Cloudflare's terms. Set allow_dlp_payload_logging = true on a pull request naming the investigation it is for, and turn it off again afterwards."
    }

    precondition {
      condition     = var.allow_disabling_dnssec_validation || length(local.dnssec_validation_disabled) == 0
      error_message = "These policies disable DNSSEC validation: ${join(", ", local.dnssec_validation_disabled)}. DNSSEC is what stops a forged answer being accepted for a signed zone, and turning it off makes that policy's resolution spoofable. The usual cause is an internal zone that is signed badly, which is a problem to fix at the zone. Set allow_disabling_dnssec_validation = true if it is genuinely the answer."
    }

    precondition {
      condition     = var.allow_untrusted_certificate_pass_through || length(local.untrusted_cert_pass_through_used) == 0
      error_message = "An untrusted certificate is set to pass through: ${join(", ", local.untrusted_cert_pass_through_used)}. The user sees no warning and the log records no failure, so an expired internal certificate and a machine-in-the-middle look identical and neither is reported. \"error\" and \"block\" both leave a trail. Set allow_untrusted_certificate_pass_through = true if the risk is understood and accepted."
    }
  }
}
