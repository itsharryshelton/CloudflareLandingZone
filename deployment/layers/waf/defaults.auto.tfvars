# Layer waf - platform baseline. Auto-loaded from this directory.
#
# Global policy, customer-agnostic. Per-account values (real corporate egress
# ranges, regulatory geoblocks) belong in accounts/<account>/waf.tfvars, which is
# passed later and therefore wins.
#
# Committed: contains no account IDs, tokens or customer names.

# Paths the block_admin_from_untrusted and log_trusted_admin_access baseline rules treat as administrative. Adjust if needed.
waf_admin_paths = [
  "/admin",
  "/wp-login.php",
  "/wp-admin",
  "/administrator",
  "/phpmyadmin",
]

# Deliberately empty. Populate per account with the real corporate egress ranges; not here.
waf_trusted_ip_ranges = []

# Deliberately empty. Geoblocking is a per-customer regulatory decision, so set it
# in the account that needs it rather than defaulting it on for everyone.
waf_blocked_countries = []
