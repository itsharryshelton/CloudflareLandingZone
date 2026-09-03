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
