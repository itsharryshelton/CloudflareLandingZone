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

output "tls_decrypt_enabled" {
  description = "Whether Gateway decrypts HTTPS for this account. False means the HTTP policies above are consulted for plaintext HTTP only, whatever the dashboard shows against them. Null means the account configuration is not managed by Terraform."
  value       = var.settings == null ? null : try(var.settings.tls_decrypt.enabled, false)
}

output "settings_managed" {
  description = "Whether this module owns the account-level Gateway configuration. False means the values in the Zero Trust dashboard are authoritative and no drift is reported against them."
  value       = var.settings != null
}

output "inspection_certificate_id" {
  description = "ID of the inspection CA this module generated, or null where the account's certificate is not managed here. This is the value that ends up in the Gateway configuration's certificate field, and the one a support case or an out-of-band API call needs."
  value       = try(cloudflare_zero_trust_gateway_certificate.this[var.account_id].id, null)
}

output "inspection_certificate_binding_status" {
  description = "Deployment state of the generated inspection CA at Cloudflare's edge - pending_deployment, available, pending_deletion or inactive. Activation is asynchronous, so a run can finish with this at pending_deployment; available is the state in which Gateway can actually decrypt with it."
  value       = try(cloudflare_zero_trust_gateway_certificate.this[var.account_id].binding_status, null)
}

output "inspection_certificate_pem" {
  description = "The generated inspection CA in PEM form. This is the public root every device on WARP has to trust before inspection is turned on, so it is the thing to hand to whatever distributes certificates - MDM, Intune, a build image. Public by nature: it is what Gateway presents to every client, and it carries no private key."
  value       = try(cloudflare_zero_trust_gateway_certificate.this[var.account_id].certificate, null)
}

output "inspection_certificate_expires_on" {
  description = "When the generated inspection CA expires. An expired inspection root is every HTTPS request failing on every device, and the replacement has to be distributed before it happens rather than after."
  value       = try(cloudflare_zero_trust_gateway_certificate.this[var.account_id].expires_on, null)
}
