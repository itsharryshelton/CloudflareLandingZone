locals {
  # WHAT IS SENT WHEN SOMETHING IS LEFT OFF
  # Provider 5.23 encodes an attribute that is null in the plan but set in state
  # as an explicit JSON null on update, and after the first refresh state holds
  # whatever the API returned (cloudflare/terraform-provider-cloudflare#7336).
  # An unset attribute is therefore only safe where the API itself reports null
  # when unset. Everywhere it reports a value instead, that value is sent:
  #   authentication, logpush, zdr  - booleans; a null logpush is refused (400)
  #   log_management(_strategy)     - from var.log_storage
  #   store_id                      - "" rather than null
  #   cache_ttl, rate limiting      - 0 for off; the provider requires them
  #   rate_limiting_technique       - "fixed" when off, as the dashboard does
  # The retry fields, the Logpush key and the dlp, guardrails and spend_limits
  # blocks are reported as null when unset, so null is what is sent for them.

  cache_ttl                  = var.cache == null ? 0 : var.cache.ttl
  cache_invalidate_on_update = var.cache == null ? false : var.cache.invalidate_on_update
  rate_limiting_limit        = var.rate_limit == null ? 0 : var.rate_limit.limit
  rate_limiting_interval     = var.rate_limit == null ? 0 : var.rate_limit.interval
  rate_limiting_technique    = var.rate_limit == null ? "fixed" : var.rate_limit.technique

  store_id = var.secrets_store_id == null ? "" : var.secrets_store_id

  # Policy mode only. The API also takes one action and profile list for the
  # whole gateway, which is a single policy checking both sides, so it adds
  # nothing a policy cannot say.
  dlp = length(var.dlp_policies) == 0 ? null : {
    enabled = anytrue([for policy in var.dlp_policies : policy.enabled])
    policies = [
      for id, policy in var.dlp_policies : {
        id       = id
        action   = policy.action
        check    = policy.check
        enabled  = policy.enabled
        profiles = policy.profiles
      }
    ]
  }

  # Cloudflare's hazard codes, from the guardrails usage considerations page.
  # The API and the provider take the codes; operators write the names, because
  # a reviewer reading `hate = "BLOCK"` knows what it does and one reading
  # `s10 = "BLOCK"` does not. variables.tf repeats the names for its validation.
  guardrail_codes = {
    violent_crimes            = "s1"
    non_violent_crimes        = "s2"
    sex_related_crimes        = "s3"
    child_sexual_exploitation = "s4"
    defamation                = "s5"
    specialized_advice        = "s6"
    privacy                   = "s7"
    intellectual_property     = "s8"
    indiscriminate_weapons    = "s9"
    hate                      = "s10"
    suicide_and_self_harm     = "s11"
    sexual_content            = "s12"
    elections                 = "s13"
    prompt_injection          = "p1"
  }

  # Every code is sent on both sides, null where the category is not acted on,
  # because the provider types both as fixed objects rather than maps.
  guardrails = var.guardrails == null ? null : {
    prompt   = { for name, code in local.guardrail_codes : code => lookup(var.guardrails.prompt, name, null) }
    response = { for name, code in local.guardrail_codes : code => lookup(var.guardrails.response, name, null) }
  }

  # The rule ID is the map key, never left to the provider: 5.23 defaults every
  # rule's ID to the same static string, so two rules without one collide.
  spend_limits = length(var.spend_limits) == 0 ? null : {
    enabled = anytrue([for rule in var.spend_limits : rule.enabled])
    rules = [
      for id, rule in var.spend_limits : {
        id                  = id
        enabled             = rule.enabled
        limit               = rule.limit
        limit_type          = "cost"
        window              = rule.window
        technique           = rule.technique
        model               = length(rule.models) == 0 ? null : { mode = "filter", values = rule.models }
        ai_gateway_provider = length(rule.providers) == 0 ? null : { mode = "filter", values = rule.providers }
        metadata = length(rule.partition_by) + length(rule.metadata_filters) == 0 ? null : merge(
          { for key in rule.partition_by : key => { mode = "partition", values = null } },
          { for key, values in rule.metadata_filters : key => { mode = "filter", values = values } },
        )
      }
    ]
  }

  # Elements are declared as a map keyed by element ID and sent as a list in
  # key order, so reordering them in tfvars is never a diff. Outputs are
  # declared as output name => target element ID and wrapped into the
  # provider's { element_id = ... } objects here.
  routes = {
    for name, route in var.routes : name => {
      elements = [
        for id, element in route.elements : {
          id   = id
          type = element.type
          outputs = {
            next     = lookup(element.outputs, "next", null) == null ? null : { element_id = element.outputs["next"] }
            "true"   = lookup(element.outputs, "true", null) == null ? null : { element_id = element.outputs["true"] }
            "false"  = lookup(element.outputs, "false", null) == null ? null : { element_id = element.outputs["false"] }
            success  = lookup(element.outputs, "success", null) == null ? null : { element_id = element.outputs["success"] }
            fallback = lookup(element.outputs, "fallback", null) == null ? null : { element_id = element.outputs["fallback"] }
          }
          # variables.tf has already refused a property on the wrong element
          # type, so every value can pass straight through.
          properties = contains(["start", "end"], element.type) ? null : {
            conditions                          = element.conditions
            key                                 = element.key
            limit                               = element.limit
            limit_type                          = element.limit_type
            window                              = element.window
            ai_gateway_dynamic_routing_provider = element.provider
            model                               = element.model
            retries                             = element.retries
            timeout                             = element.timeout
          }
        }
      ]
    }
  }

  # Derived assertions, consumed by the preconditions in main.tf.

  # Features Cloudflare only offers on an authenticated gateway.
  needs_authentication = sort(compact([
    length(var.routes) > 0 ? "routes" : "",
    var.secrets_store_id != null ? "secrets_store_id (BYOK)" : "",
    var.zero_data_retention ? "zero_data_retention" : "",
  ]))

  # Every edge of every route, for the graph checks below.
  route_edges = {
    for name, route in var.routes : name => flatten([
      for id, element in route.elements : [
        for output, target in element.outputs : { from = id, output = output, to = target }
      ]
    ])
  }

  # Route name => what is wrong with its graph, so a failing route names only
  # itself. Cycles are not looked for: a loop through fallbacks is legal to
  # declare, and whether the API refuses one is not documented.
  route_problems = {
    for name, route in var.routes : name => concat(
      length([for element in route.elements : element if element.type == "start"]) == 1 ? [] : [
        "it must have exactly one start element, and has ${length([for element in route.elements : element if element.type == "start"])}"
      ],
      length([for element in route.elements : element if element.type == "end"]) > 0 ? [] : [
        "it has no end element, so no path through it can finish"
      ],
      [
        for edge in local.route_edges[name] : "${edge.from}.${edge.output} points at \"${edge.to}\", which is not an element of this route"
        if !contains(keys(route.elements), edge.to)
      ],
      [
        for edge in local.route_edges[name] : "${edge.from}.${edge.output} points at itself"
        if edge.from == edge.to
      ],
      [
        for edge in local.route_edges[name] : "${edge.from}.${edge.output} points back at the start element"
        if try(route.elements[edge.to].type, "") == "start"
      ],
      [
        for id, element in route.elements : "\"${id}\" is never reached - no output points at it"
        if element.type != "start" && !contains([for edge in local.route_edges[name] : edge.to], id)
      ],
    )
  }
}
