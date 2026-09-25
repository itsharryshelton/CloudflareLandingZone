# Layer waf - platform baseline. Auto-loaded from this directory.
#
# Global policy, customer-agnostic. Per-account values (real corporate egress
# ranges, regulatory geoblocks) belong in accounts/<account>/waf.tfvars, which is
# passed later and therefore wins.
#
# Committed: contains no account IDs, tokens or customer names.

# Paths the block_admin_from_untrusted and log_trusted_admin_access baseline rules
# treat as administrative. Matched with `contains`, so "/admin" also covers
# "/admin/config".

# NOTE: Add your own admin paths here
waf_admin_paths = [
  # Generic
  "/admin",
  "/administrator",
  "/phpmyadmin",

  # WordPress
  "/wp-login.php",
  "/wp-admin",

  # Typical Login Points - Recommend to adjust if needed / note this will autoblock login paths if not on trusted IPs (Not useful if being deployed to public website)
  "/user/login",
  "/user/password",
  "/user/register",
]

# Deliberately empty. Populate per account with the real corporate egress ranges; not here.
waf_trusted_ip_ranges = []

# Deliberately empty. Geoblocking is a per-customer regulatory decision, so set it
# in the account that needs it rather than defaulting it on for everyone.
waf_blocked_countries = []

# Must match the zones layer's default_zone_tier
default_zone_tier = "free"

# Lowest plan allowed to carry bot_traffic rules
bot_traffic_min_tier = "pro"

# Lowest plan allowed to carry managed rulesets
managed_rules_min_tier = "enterprise"

# OWASP tuning for Managed Ruleset
waf_owasp_paranoia_level  = 1
waf_owasp_score_threshold = 40

# Deliberately empty. The routes that accept HTML depend on the application, so
# set them per account next to the hostnames that use them.
waf_html_submission_paths = []

# Cloudflare Managed rules skipped by html_submission. Empty until Security
# Events shows one blocking a legitimate submission; rule IDs are global, so an
# ID added here applies to every account.
waf_html_submission_skip_rule_ids = []
