# Account: account_a - WAF policies. Consumed by the waf layer only.
#
#   terraform -chdir=layers/waf plan \
#     -var-file=../../accounts/account_a/account.tfvars \
#     -var-file=../../accounts/account_a/zones.tfvars \
#     -var-file=../../accounts/account_a/waf.tfvars
#
# Baseline rules are chosen by name from the catalogue in layers/waf/locals.waf.tf. Only genuinely bespoke logic needs a raw expression.

# The corporate egress ranges. This overrides the empty default in layers/waf/defaults.auto.tfvars, and the baseline admin rules below depend on.
# anything not listed here is treated as untrusted, although one could argue never trust by just IP :)
waf_trusted_ip_ranges = [
  "203.0.113.0/24",
  "198.51.100.7",
]

waf_policies = {
  primary = {
    zone_key = "primary"

    baseline_custom_rules = [
      "block_admin_from_untrusted",
      "block_known_exploit_paths",
      "log_trusted_admin_access",
    ]

    baseline_rate_limits = [
      "auth_brute_force",
      "api_general",
    ]

    # Appended after the baseline rules, so it evaluates later.
    custom_block_rules = [
      {
        name        = "Block legacy XML-RPC endpoint"
        expression  = "http.request.uri.path eq \"/xmlrpc.php\""
        action      = "block"
        description = "Unused by this application and heavily probed."
      },
    ]
  }

  # No entry for "mail": that zone proxies nothing, so there is no edge traffic to
  # filter. The waf layer will not look it up or create any ruleset for it.
}
