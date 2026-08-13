# Platform Gateway baseline catalogue.
#
# The Secure Web Gateway rules a deployment is likely to want on every account.
#
# Every entry carries the same attribute set, including the ones it does not use,
# because Terraform needs one type across the map.

locals {
  gateway_baseline_catalogue = {
    # Cheapest enforcement point there is: the answer is refused before a
    # connection exists, so nothing is dialled and nothing is decrypted.
    block_security_threats = {
      name        = "Baseline - block security threats (DNS)"
      type        = "dns"
      action      = "block"
      precedence  = 10
      description = "Baseline - block Cloudflare security categories at DNS"

      security_categories = var.gateway_security_categories
      content_categories  = []
      applications        = []
      dlp_profile_ids     = []
      download_file_types = []

      block_reason          = "This site is categorised as a security threat."
      block_page_enabled    = true
      quarantine_file_types = null
    }

    # The same categories again at L7, and not redundant. A DNS policy only sees
    # the queries that come to Gateway's resolver, and a browser resolving over
    # DNS-over-HTTPS to somebody else's resolver never sends one. The HTTP policy
    # sees the connection either way.
    block_security_threats_http = {
      name        = "Baseline - block security threats (HTTP)"
      type        = "http"
      action      = "block"
      precedence  = 20
      description = "Baseline - block Cloudflare security categories at HTTP, for clients that do not use Gateway's resolver"

      security_categories = var.gateway_security_categories
      content_categories  = []
      applications        = []
      dlp_profile_ids     = []
      download_file_types = []

      block_reason          = "This site is categorised as a security threat."
      block_page_enabled    = null
      quarantine_file_types = null
    }

    block_disallowed_content = {
      name        = "Baseline - block disallowed content categories"
      type        = "dns"
      action      = "block"
      precedence  = 20
      description = "Baseline - block the content categories this account does not permit"

      security_categories = []
      content_categories  = var.gateway_blocked_content_categories
      applications        = []
      dlp_profile_ids     = []
      download_file_types = []

      block_reason          = "This site is in a category the organisation does not permit."
      block_page_enabled    = true
      quarantine_file_types = null
    }

    # Do Not Inspect policy
    bypass_trusted_applications = {
      name        = "Baseline - do not inspect trusted applications"
      type        = "http"
      action      = "off"
      precedence  = 10
      description = "Baseline - bypass TLS inspection for applications that cannot tolerate it"

      security_categories = []
      content_categories  = []
      applications        = var.gateway_bypass_applications
      dlp_profile_ids     = []
      download_file_types = []

      block_reason          = null
      block_page_enabled    = null
      quarantine_file_types = null
    }

    block_dlp_matches = {
      name        = "Baseline - block DLP matches"
      type        = "http"
      action      = "block"
      precedence  = 30
      description = "Baseline - block requests whose body matches a DLP profile"

      security_categories = []
      content_categories  = []
      applications        = []
      dlp_profile_ids     = var.gateway_dlp_profile_ids
      download_file_types = []

      block_reason          = "This request contained data the organisation does not permit to be sent to this destination."
      block_page_enabled    = null
      quarantine_file_types = null
    }

    quarantine_risky_downloads = {
      name        = "Baseline - quarantine risky downloads"
      type        = "http"
      action      = "quarantine"
      precedence  = 40
      description = "Baseline - detonate executable downloads in Cloudflare's file sandbox before delivering them"

      security_categories = []
      content_categories  = []
      applications        = []
      dlp_profile_ids     = []
      download_file_types = var.gateway_quarantine_file_types

      block_reason          = null
      block_page_enabled    = null
      quarantine_file_types = var.gateway_quarantine_file_types
    }
  }

  # Guards: which baseline needs which variable populated
  gateway_baseline_requirements = {
    block_security_threats = {
      satisfied = length(var.gateway_security_categories) > 0
      reason    = "gateway_security_categories is empty, so this rule would block nothing and `any(dns.security_category[*] in {})` is not a valid Cloudflare expression."
    }
    block_security_threats_http = {
      satisfied = length(var.gateway_security_categories) > 0
      reason    = "gateway_security_categories is empty, so this rule would block nothing."
    }
    block_disallowed_content = {
      satisfied = length(var.gateway_blocked_content_categories) > 0
      reason    = "gateway_blocked_content_categories is empty. Which content categories an account blocks is an acceptable-use decision, so there is no default that could be assumed here."
    }
    bypass_trusted_applications = {
      satisfied = length(var.gateway_bypass_applications) > 0
      reason    = "gateway_bypass_applications is empty, so this rule would exempt nothing from inspection while appearing in the dashboard as a bypass."
    }
    block_dlp_matches = {
      satisfied = length(var.gateway_dlp_profile_ids) > 0
      reason    = "gateway_dlp_profile_ids is empty. DLP profiles are defined in the Zero Trust dashboard and referenced by UUID; without one there is nothing for this rule to match."
    }
    quarantine_risky_downloads = {
      satisfied = length(var.gateway_quarantine_file_types) > 0
      reason    = "gateway_quarantine_file_types is empty, so this rule would quarantine nothing."
    }
  }
}
