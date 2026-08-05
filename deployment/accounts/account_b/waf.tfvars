# Account: account_b - WAF policies. Consumed by the waf layer only.
#
#   terraform -chdir=layers/waf plan \
#     -var-file=../../accounts/account_b/account.tfvars \
#     -var-file=../../accounts/account_b/zones.tfvars \
#     -var-file=../../accounts/account_b/waf.tfvars
#
# Baseline rules are chosen by name from the catalogue in layers/waf/locals.waf.tf. Only genuinely bespoke logic needs a raw expression.

# The corporate egress ranges. This overrides the empty default in layers/waf/defaults.auto.tfvars, and the baseline admin rules below depend on.
# anything not listed here is treated as untrusted, although one could argue never trust by just IP :)
waf_trusted_ip_ranges = [
  "198.51.100.0/24",
]

# A regulated market example, so this customer geoblocks. Note that layers/waf/defaults.auto.tfvars leaves waf_blocked_countries empty on purpose - geoblocking is a per-customer regulatory decision, not a platform default.
waf_blocked_countries = ["CN", "RU", "IR", "KP"]

waf_policies = {
  primary = {
    zone_key = "primary"

    baseline_custom_rules = [
      "geoblock_countries",
      "block_admin_from_untrusted",
      "block_known_exploit_paths",
      "challenge_undisclosed_bots",
    ]

    # Observe first: this zone has no traffic history to size a limit from.
    baseline_rate_limits = [
      "observe_only",
    ]
  }
}
