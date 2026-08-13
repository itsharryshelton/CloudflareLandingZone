# Cloudflare Gateway - the Secure Web Gateway policy set for one account.
#
# Three enforcement pipelines, not one list: a DNS policy is resolved before a
# connection exists, a network policy sees the L4 connection and the TLS SNI, and
# an HTTP policy sees the decrypted request. Gateway walks each in ascending
# precedence and stops at the first allow or block that matches, which is why
# precedence is an input here rather than something derived from list order.
#
# Expression compilation lives in locals.tf. The preconditions below are the
# checks that need more than one input, so they cannot be variable validations.
resource "cloudflare_zero_trust_gateway_policy" "this" {
  for_each = local.policies

  account_id  = var.account_id
  name        = trimspace(each.value.name)
  description = coalesce(each.value.description, trimspace(each.value.name))
  action      = each.value.action
  enabled     = each.value.enabled
  precedence  = each.value.precedence
  filters     = [local.policy_filters[each.value.type]]

  # Sent only where the policy actually restricts on that dimension. An empty
  # string is not "match nothing" to Cloudflare, it is a parse error.
  traffic        = local.traffic[each.key] == "" ? null : local.traffic[each.key]
  identity       = local.identity[each.key] == "" ? null : local.identity[each.key]
  device_posture = local.device_posture[each.key] == "" ? null : local.device_posture[each.key]

  rule_settings = local.rule_settings[each.key]
  schedule      = each.value.schedule
  expiration    = each.value.expiration

  lifecycle {
    precondition {
      condition     = length(local.invalid_actions) == 0
      error_message = "These policies use an action their policy type does not have: ${join("; ", local.invalid_actions)}. DNS policies take allow, block, override, safesearch or ytrestricted. Network policies take allow, block or l4_override. HTTP policies take allow, block, off, on, scan, noscan, isolate, noisolate, quarantine or redirect. The provider's enum covers every builder at once, so the wrong one is rejected by the Cloudflare API at apply rather than at plan."
    }

    precondition {
      condition     = length(local.unsupported_selectors) == 0
      error_message = "These selectors do not exist for the policy type they were used on: ${join("; ", local.unsupported_selectors)}. A DNS policy is resolved before there is a connection, so it has no port, protocol or file type. A network policy sees the TLS SNI rather than an HTTP Host header, so it takes sni_domains and sni_hosts instead of domains and hosts. Only an HTTP policy is past decryption, so only an HTTP policy can match a DLP profile, a method or a file type."
    }

    precondition {
      condition     = length(local.duplicate_precedences) == 0
      error_message = "Two policies of the same type share a precedence: ${join("; ", local.duplicate_precedences)}. Precedence is the evaluation order within a builder and Gateway stops at the first allow or block that matches, so a tie means the enforced order is Cloudflare's choice rather than yours. Precedence is per type, so a DNS and an HTTP policy may share a number."
    }

    # A policy with no traffic, identity or device posture expression matches
    # every request of its type. That is occasionally the intent - a final
    # default-deny - and it is never something that should happen because a
    # selector was misspelled into a field that does not exist.
    precondition {
      condition     = length(local.policies_with_no_selector) == 0
      error_message = "These policies name no selector at all and would therefore match every request of their type: ${join(", ", local.policies_with_no_selector)}. Give them a match, an identity or a device posture condition, or set match_all_traffic = true if a catch-all is genuinely the intent."
    }

    precondition {
      condition     = length(local.unscoped_permissive_policies) == 0
      error_message = "These policies combine match_all_traffic with an action that removes enforcement: ${join("; ", local.unscoped_permissive_policies)}. Gateway stops at the first allow it matches, so an unscoped allow does not mean \"permissive by default\" - it means every policy below it is never reached. An unscoped \"off\" turns TLS inspection off for the whole account. A catch-all may only block, isolate, scan or redirect."
    }

    # The Microsoft 365 trap. A bypass written with a selector Gateway cannot see
    # before decryption is not rejected - it just never matches, and the traffic
    # keeps being inspected while the dashboard shows the bypass as configured.
    precondition {
      condition     = length(local.do_not_inspect_needing_decryption) == 0
      error_message = "A Do Not Inspect policy (action = \"off\") matches on something only visible after TLS decryption: ${join("; ", local.do_not_inspect_needing_decryption)}. Do Not Inspect is evaluated before decryption, so it can only match on the TLS handshake and the hostname - applications, domains, hosts, categories and IPs. The rule as written would never match, and the traffic it was meant to exempt would keep being decrypted."
    }

    precondition {
      condition     = length(local.dlp_with_incompatible_action) == 0
      error_message = "These policies match on a DLP profile but use an action that stops the request body being scanned: ${join("; ", local.dlp_with_incompatible_action)}. A DLP match is produced by the scan, so \"off\" and \"noscan\" cannot act on one. Use block, isolate or quarantine."
    }

    precondition {
      condition = (
        length(local.conflicting_traffic_definitions) == 0 &&
        length(local.conflicting_identity_definitions) == 0 &&
        length(local.conflicting_device_posture_definitions) == 0
      )
      error_message = "These policies set both a structured matcher and a raw expression for the same dimension - traffic: ${join(", ", local.conflicting_traffic_definitions)}; identity: ${join(", ", local.conflicting_identity_definitions)}; device posture: ${join(", ", local.conflicting_device_posture_definitions)}. The raw expression replaces the compiled one rather than being merged with it, so one of the two would be silently discarded. Express the whole condition one way or the other."
    }

    precondition {
      condition     = length(local.actions_missing_settings) == 0
      error_message = "These policies use an action that needs a setting to go with it: ${join("; ", local.actions_missing_settings)}. Cloudflare has nowhere to redirect to, no file types to quarantine, no address to override to, and rejects the rule."
    }

    precondition {
      condition = (
        length(local.dns_only_settings) == 0 &&
        length(local.http_only_settings) == 0 &&
        length(local.network_only_settings) == 0
      )
      error_message = "These settings were given to a policy type that does not honour them - DNS-only: ${join(", ", local.dns_only_settings)}; HTTP-only: ${join(", ", local.http_only_settings)}; network-only: ${join(", ", local.network_only_settings)}. Cloudflare drops a setting it has no use for, so the policy would be shown configured one way and enforced another."
    }
  }
}
