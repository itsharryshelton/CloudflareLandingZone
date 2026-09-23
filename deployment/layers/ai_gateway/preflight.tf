resource "terraform_data" "preflight" {
  input = {
    ai_gateways = length(var.ai_gateways)
    # Surfaced in the plan because it is the setting that decides who can use
    # a gateway at all, and the one a reviewer should never have to go looking for.
    authentication = { for key, gateway in local.gateways : key => gateway.authentication }
  }

  lifecycle {
    precondition {
      condition     = length(local.duplicate_gateway_ids) == 0
      error_message = "Two keys declare the same gateway_id: ${join("; ", local.duplicate_gateway_ids)}. A gateway ID is unique per account, so Cloudflare refuses the second at apply, after the plan was approved."
    }

    precondition {
      condition     = length(local.gateways) <= var.max_ai_gateways
      error_message = "This account declares ${length(local.gateways)} gateways, over max_ai_gateways (${var.max_ai_gateways}). Cloudflare allows 10 per account on Workers Free and 20 on Workers Paid, and refuses the rest at apply. Merge gateways, or raise max_ai_gateways in layers/ai_gateway/defaults.auto.tfvars once the account's limit has been raised."
    }

    precondition {
      condition     = var.allow_unauthenticated_gateways || length(local.unauthenticated_gateways) == 0
      error_message = "These gateways set authentication = false: ${join(", ", local.unauthenticated_gateways)}. Anyone who knows the account ID and gateway ID - neither is a secret - can then send requests through them, filling their logs and spending their rate limits. Turn authentication on, or set allow_unauthenticated_gateways = true in layers/ai_gateway/defaults.auto.tfvars on a pull request that says why."
    }
  }
}
