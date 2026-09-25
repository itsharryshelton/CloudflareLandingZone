# Platform WAF baseline catalogue.
#
# The rules a deployment is likely to want on every zone, expressed once here and
# opted into by name from `waf_policies[*].baseline_custom_rules`,
# `baseline_rate_limits`, `baseline_managed_rulesets` and
# `baseline_managed_exceptions`. Nothing here is customer-specific: the
# addresses, paths, hostnames and country codes come from variables, so the same
# catalogue serves every tenant.
#
# Adding a rule here: give it a stable name (the name is the operator-facing API
# and appears in the Cloudflare dashboard), and if it depends on a variable being
# populated, add the guard to `local.waf_baseline_requirements` at the bottom.

locals {
  # Cloudflare set literal for IPs and CIDRs: e.g. {203.0.113.0/24 198.51.100.7}
  waf_trusted_ip_set = "{${join(" ", var.waf_trusted_ip_ranges)}}"

  # Country codes are quoted inside the set: {"CN" "RU"}
  waf_blocked_country_set = "{${join(" ", [for code in var.waf_blocked_countries : "\"${code}\""])}}"

  # ( path contains "/admin" or path contains "/wp-login.php" )
  waf_admin_path_clause = join(" or ", [
    for path in var.waf_admin_paths : "http.request.uri.path contains \"${path}\""
  ])

  # Baseline custom firewall rules (http_request_firewall_custom)
  waf_baseline_custom_rules = {
    block_admin_from_untrusted = {
      name        = "Baseline - restrict admin paths to trusted networks"
      expression  = "(${local.waf_admin_path_clause}) and not ip.src in ${local.waf_trusted_ip_set}"
      action      = "block"
      description = "Baseline - restrict admin paths to trusted networks"
      enabled     = true
    }

    geoblock_countries = {
      name        = "Baseline - block disallowed countries"
      expression  = "ip.geoip.country in ${local.waf_blocked_country_set}"
      action      = "block"
      description = "Baseline - block disallowed countries"
      enabled     = true
    }

    block_listed_ips = {
      name        = "Baseline - block addresses on the account IP blocklist"
      expression  = format("ip.src in $%s", coalesce(var.waf_ip_blocklist_name, "unset"))
      action      = "block"
      description = "Baseline - block addresses on the account IP blocklist"
      enabled     = true
    }

    block_known_exploit_paths = {
      name = "Baseline - block probes for common exploit paths"
      expression = join(" or ", [
        "http.request.uri.path contains \"/.env\"",
        "http.request.uri.path contains \"/.git/\"",
        "http.request.uri.path contains \"/vendor/phpunit\"",
        "http.request.uri.path contains \"/.aws/\"",
        "http.request.uri.path eq \"/.DS_Store\"",
      ])
      action      = "block"
      description = "Baseline - block probes for common exploit paths"
      enabled     = true
    }

    challenge_undisclosed_bots = {
      name        = "Baseline - challenge unverified automated traffic"
      expression  = "cf.client.bot eq false and cf.threat_score gt 14 and not ip.src in ${local.waf_trusted_ip_set}"
      action      = "managed_challenge"
      description = "Baseline - challenge unverified automated traffic"
      enabled     = true
    }

    log_trusted_admin_access = {
      # Observability rather than mitigation: records who reached an admin path from a trusted range. Pair with block_admin_from_untrusted.
      name        = "Baseline - log admin access from trusted networks"
      expression  = "(${local.waf_admin_path_clause}) and ip.src in ${local.waf_trusted_ip_set}"
      action      = "log"
      description = "Baseline - log admin access from trusted networks"
      enabled     = true
    }
  }

  # Baseline rate limits (http_ratelimit)
  waf_baseline_rate_limits = {
    auth_brute_force = {
      name                = "Baseline - authentication brute force"
      expression          = "http.request.uri.path contains \"/login\" or http.request.uri.path contains \"/auth\""
      period              = 60
      requests            = 20
      mitigation_action   = "block"
      mitigation_timeout  = 600
      characteristics     = ["ip.src"]
      counting_expression = null
      requests_to_origin  = false
      enabled             = true
    }

    api_general = {
      name                = "Baseline - general API ceiling"
      expression          = "starts_with(http.request.uri.path, \"/api/\")"
      period              = 60
      requests            = 600
      mitigation_action   = "managed_challenge"
      mitigation_timeout  = 60
      characteristics     = ["ip.src"]
      counting_expression = null
      requests_to_origin  = false
      enabled             = true
    }

    origin_error_shield = {
      # Counts only requests the origin answered with 5xx, so a failing backend is not hammered while it recovers.
      name                = "Baseline - back off when origin is failing"
      expression          = "not starts_with(http.request.uri.path, \"/healthz\")"
      period              = 60
      requests            = 50
      mitigation_action   = "block"
      mitigation_timeout  = 60
      characteristics     = ["ip.src"]
      counting_expression = "http.response.code ge 500"
      requests_to_origin  = true
      enabled             = true
    }

    observe_only = {
      # Deliberately log-only: use it to size a limit before enforcing one. mitigation_timeout is omitted because the waf module forces 0 for log.
      name                = "Baseline - observe request rates without enforcing"
      expression          = "not starts_with(http.request.uri.path, \"/healthz\")"
      period              = 60
      requests            = 1000
      mitigation_action   = "log"
      mitigation_timeout  = null
      characteristics     = ["ip.src"]
      counting_expression = null
      requests_to_origin  = false
      enabled             = true
    }
  }

  # Cloudflare Managed Rulesets (http_request_firewall_managed)

  # Global constants, the same in every account
  waf_managed_ruleset_ids = {
    cloudflare_managed = "efb7b8c949ac4650a09736fc376e9aee"
    owasp_core         = "4814384a9e5d4991b9815dcfc25d2f1f"
  }

  # The only OWASP rule that acts: every other one adds to an anomaly score that
  # this rule compares against the threshold.
  waf_owasp_anomaly_rule_id = "6179ae15870a4bb7b2d480d4843b323c"

  waf_owasp_disabled_paranoia_levels = [
    for level in [2, 3, 4] : "paranoia-level-${level}"
    if level > var.waf_owasp_paranoia_level
  ]
  waf_managed_override_shape = {
    action            = null
    enabled           = null
    sensitivity_level = null
    categories        = []
    rules             = []
  }

  waf_baseline_managed_rulesets = {
    cloudflare_managed = {
      id          = local.waf_managed_ruleset_ids.cloudflare_managed
      version     = null
      expression  = "true"
      description = "Baseline - Cloudflare Managed Ruleset"
      enabled     = true
      overrides = merge(local.waf_managed_override_shape, {
        # Null leaves every rule on the action Cloudflare ships it with.
        action = var.waf_managed_rules_action
      })
    }

    owasp_core = {
      id          = local.waf_managed_ruleset_ids.owasp_core
      version     = null
      expression  = "true"
      description = "Baseline - Cloudflare OWASP Core Ruleset"
      enabled     = true
      overrides = merge(local.waf_managed_override_shape, {
        categories = [
          for tag in local.waf_owasp_disabled_paranoia_levels : {
            category          = tag
            action            = null
            enabled           = false
            sensitivity_level = null
          }
        ]

        # OWASP is scored rather than per-rule
        rules = [
          {
            id                = local.waf_owasp_anomaly_rule_id
            action            = var.waf_owasp_action
            enabled           = null
            score_threshold   = var.waf_owasp_score_threshold
            sensitivity_level = null
          }
        ]
      })
    }
  }

  # Baseline WAF exceptions (http_request_firewall_managed, ahead of the managed
  # rulesets). A policy supplies the hostnames each one covers, so an entry here
  # carries only the method, the paths and what to skip. `rules` is keyed by
  # ruleset, and a policy only skips the rulesets it executes.

  # Anchored at both ends so each entry matches one route shape, never a prefix
  waf_html_submission_path_regex = format("^(%s)$", join("|", var.waf_html_submission_paths))

  waf_html_submission_method_set = "{${join(" ", [for method in var.waf_html_submission_methods : "\"${method}\""])}}"

  waf_baseline_managed_exceptions = {
    html_submission = {
      # These routes accept exactly the markup injection signatures exist to
      # catch. OWASP's verdict is skipped outright, since anomaly scoring cannot
      # tell legitimate markup from an attack, but only the listed Cloudflare
      # Managed rules are - the rest of that ruleset keeps running.
      name       = "Baseline - HTML submission routes skip HTML injection signatures"
      expression = "http.request.method in ${local.waf_html_submission_method_set} and http.request.uri.path matches \"${local.waf_html_submission_path_regex}\""
      rules = {
        (local.waf_managed_ruleset_ids.cloudflare_managed) = distinct(var.waf_html_submission_skip_rule_ids)
        (local.waf_managed_ruleset_ids.owasp_core)         = [local.waf_owasp_anomaly_rule_id]
      }
    }
  }

  # Guards: which baseline rules need which variable populated. Selecting a rule whose parameter list is empty is not a cosmetic problem. An empty trusted IP set turns block_admin_from_untrusted into "block all admin traffic", and an empty country set produces an expression Cloudflare rejects. Enforced by preconditions in waf.tf.
  waf_baseline_requirements = {
    block_admin_from_untrusted = {
      satisfied = length(var.waf_trusted_ip_ranges) > 0
      reason    = "waf_trusted_ip_ranges is empty, so this rule would block administrative access from every source, including yours."
    }
    challenge_undisclosed_bots = {
      satisfied = length(var.waf_trusted_ip_ranges) > 0
      reason    = "waf_trusted_ip_ranges is empty, so this rule would challenge trusted automation as well."
    }
    log_trusted_admin_access = {
      satisfied = length(var.waf_trusted_ip_ranges) > 0
      reason    = "waf_trusted_ip_ranges is empty, so this rule could never match."
    }
    geoblock_countries = {
      satisfied = length(var.waf_blocked_countries) > 0
      reason    = "waf_blocked_countries is empty, and `ip.geoip.country in {}` is not a valid Cloudflare expression."
    }
    block_listed_ips = {
      satisfied = var.waf_ip_blocklist_name != null
      reason    = "waf_ip_blocklist_name is unset, so this rule would reference a list called $unset. Cloudflare rejects a rule naming a list that does not exist, which fails the apply after some rules have already been written."
    }
    html_submission = {
      satisfied = length(var.waf_html_submission_paths) > 0 && length(var.waf_html_submission_methods) > 0
      reason    = "waf_html_submission_paths and waf_html_submission_methods must both be set. The routes are application-specific, so the platform ships no default, and an empty method set produces `in {}`, which Cloudflare rejects."
    }
  }
}
