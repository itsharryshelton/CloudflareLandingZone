output "policy_ids" {
  description = "Gateway policy ID per normalised policy name. This is what a Cloudflare support case, an audit export or an out-of-band API call needs to identify a rule."
  value       = { for key, policy in cloudflare_zero_trust_gateway_policy.this : key => policy.id }
}

output "policies_by_type" {
  description = "Normalised policy names grouped by policy type, each list in the order Gateway evaluates them. This is the enforced rule order, which is the thing worth reading back after an apply - a rule that moved is a rule that may now be shadowed by the one above it."
  value = {
    # Sorted through a zero-padded precedence prefix, because sort() is
    # lexicographic and "100" would otherwise come before "20".
    for type, ordered in local.ordered_policy_keys_by_type : type => ordered
  }
}

output "policy_precedence" {
  description = "Precedence per normalised policy name, alongside the policy type it is ordered within. Precedence is per type, so two policies of different types sharing a number are not in conflict."
  value = {
    for key, policy in local.policies : key => {
      type       = policy.type
      precedence = policy.precedence
    }
  }
}

output "policy_expressions" {
  description = "The compiled Cloudflare wirefilter expressions per normalised policy name - traffic, identity and device posture. Read this to see exactly what a set of selectors turned into before trusting it, and to copy an expression into the Gateway dashboard's expression editor when reproducing a match."
  value = {
    for key in keys(local.policies) : key => {
      traffic        = local.traffic[key]
      identity       = local.identity[key]
      device_posture = local.device_posture[key]
    }
  }
}

output "policies_logging_dlp_payloads" {
  description = "Normalised names of the policies with DLP payload logging turned on. Those policies write the matched content itself - the card number, the identifier, the source code fragment - into Gateway's logs, where anyone with log access can read it. Empty is the expected state."
  value       = local.policies_logging_dlp_payloads
}
