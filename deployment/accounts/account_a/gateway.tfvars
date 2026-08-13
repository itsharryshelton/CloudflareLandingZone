# Account: account_a - Cloudflare Gateway (Secure Web Gateway).
#
# Three enforcement pipelines, ordered independently of each other
#
# Precedence below 100 is reserved for the platform baseline in
# layers/gateway/locals.gateway.tf.

# Platform baseline
gateway_baseline_policies = [
  "block_security_threats",
  "block_security_threats_http",
  "bypass_trusted_applications",
  "block_dlp_matches",
  "quarantine_risky_downloads",
]

# Applications exempted from TLS inspection.
#
# Naming the application rather than its hostnames means Cloudflare maintains the hostnames.
gateway_bypass_applications = ["Microsoft 365"]

# DLP profiles are defined in the Zero Trust dashboard under DLP and referenced
# by UUID - Cloudflare exposes no way to resolve one by name - needs updating.
gateway_dlp_profile_ids = [
  "33333333-3333-3333-3333-333333333333",
]

# Executables and archives are detonated in Cloudflare's sandbox before delivery.
# Kept short: quarantine makes the user wait for the scan. The sandbox accepts a
# fixed set of formats and "dll" and "scr" are not among them.
gateway_quarantine_file_types = ["exe", "zip", "rar"]

# Acceptable use rather than security
gateway_blocked_content_categories = []

# Account policies
gateway_policies = {
  # DNS
  block_known_bad_domains = {
    name        = "Block known bad domains"
    type        = "dns"
    action      = "block"
    precedence  = 100
    description = "Domains this account has decided not to resolve, beyond what the security categories already cover"

    # `domains` matches the domain and every subdomain of it. Use `hosts` for one exact name.
    match = {
      domains = ["example.net"]
    }

    settings = {
      block_reason       = "This domain is blocked by your organisation."
      block_page_enabled = true
    }
  }

  # Network (L4)
  # These two are a pair, and the precedences are the point: the allow is
  # evaluated first, so mail to the sanctioned relay survives the block below it.
  allow_sanctioned_smtp_relay = {
    name        = "Allow the sanctioned SMTP relay"
    type        = "network"
    action      = "allow"
    precedence  = 100
    description = "Mail submission to the relay the organisation runs"

    match = {
      destination_ip_cidrs = ["203.0.113.25/32"]
      destination_ports    = [587]
      protocols            = ["tcp"]
    }
  }

  block_direct_smtp = {
    name        = "Block direct outbound SMTP"
    type        = "network"
    action      = "block"
    precedence  = 110
    description = "Outbound mail that does not go through the relay - the usual sign of a compromised host or an application nobody registered"

    match = {
      destination_ports = [25, 465, 587]
      protocols         = ["tcp"]
    }

    settings = {
      block_reason = "Outbound mail must go through the organisation's relay."
    }
  }

  # HTTP
  isolate_contractor_browsing = {
    name        = "Isolate contractor browsing"
    type        = "http"
    action      = "isolate"
    precedence  = 100
    description = "Contractors browse through Browser Isolation, so nothing executes on their device"

    # No traffic selector at all: this policy is scoped by who the user is rather than by where they are going.
    identity = {
      user_group_names = ["Contractors"]
    }
  }

  block_uploads_to_unmanaged_storage = {
    name        = "Block uploads to unmanaged storage"
    type        = "http"
    action      = "block"
    precedence  = 120
    description = "Files leaving for storage the organisation does not control"

    # Destination terms are OR'd; the file-type constraint is AND'd against them. So: an upload of one of these types, to either of these domains.
    match = {
      domains           = ["example.org"]
      upload_file_types = ["pdf", "docx", "xlsx"]
    }

    settings = {
      block_reason = "Files may only be uploaded to storage the organisation manages."
    }
  }

  # Out of hours, and only on weekdays.
  block_streaming_during_work_hours = {
    name        = "Block streaming during work hours"
    type        = "http"
    action      = "block"
    precedence  = 130
    description = "Bandwidth management rather than security"
    enabled     = false

    match = {
      domains = ["example.com"]
    }

    schedule = {
      time_zone = "Europe/London"
      mon       = "09:00-12:30,13:30-17:30"
      tue       = "09:00-12:30,13:30-17:30"
      wed       = "09:00-12:30,13:30-17:30"
      thu       = "09:00-12:30,13:30-17:30"
      fri       = "09:00-12:30,13:30-17:30"
    }
  }
}
