variable "account_id" {
  type        = string
  description = "Cloudflare Account ID. A gateway is account-scoped, attached to no zone, and its endpoint URL carries this ID."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "gateway_id" {
  type        = string
  description = <<-EOT
    The gateway's ID. It is also its name in the dashboard and the path segment
    every client puts in its base URL:
      https://gateway.ai.cloudflare.com/v1/<account_id>/<gateway_id>/<provider>

    FIXED AT CREATION. Changing it replaces the gateway: a new, empty one is
    created under the new ID and the old one is deleted, with its logs and
    dynamic routes. Every client still configured with the old URL fails from
    that moment, and BYOK secrets named after the old ID stop being found.

    "default" is Cloudflare's own gateway, created by the first authenticated
    request that names no gateway. It usually exists already, so it has to be
    imported rather than created, and deleting it only lasts until the next
    such request.

    1-64 characters: lowercase letters, digits and underscores, in groups
    joined by single hyphens. That is Cloudflare's rule.
  EOT

  validation {
    condition     = length(var.gateway_id) <= 64 && can(regex("^[a-z0-9_]+(?:-[a-z0-9_]+)*$", var.gateway_id))
    error_message = "gateway_id must be 1-64 characters of lowercase letters, digits and underscores, in groups joined by single hyphens - e.g. \"support-assistant\". No leading, trailing or doubled hyphens."
  }
}

variable "authentication" {
  type        = bool
  default     = true
  description = <<-EOT
    Authenticated gateway. When true, a request to the gateway endpoint must
    carry `cf-aig-authorization: Bearer <token>`, where the token is a
    Cloudflare API token with AI Gateway Run, or it is refused. A request made
    through a Worker binding is authenticated already.

    When false, the gateway serves anyone who knows its URL, and the URL is
    built from the account ID and the gateway ID - neither of them a secret.
    They can fill its logs, spend its rate limit and read from its cache.

    Routes, BYOK and Zero Data Retention all need it on; the plan fails
    otherwise.

    A Run token cannot be scoped to one gateway. Whoever holds one can use
    every gateway on the account, BYOK keys included. This module does not
    create it: it is the application's credential, not this pipeline's.
  EOT
}

variable "collect_logs" {
  type        = bool
  default     = true
  description = <<-EOT
    Store a log of every request: the prompt, the response, the provider and
    model, token counts, cost and latency. Analytics, the log explorer and
    Logpush are all built on it.

    It is also a copy of everything every user sent, kept at Cloudflare with no
    time limit - only the count cap in log_storage - and readable by any token
    with AI Gateway Read. A client can skip one request with
    `cf-aig-collect-log: false`, or keep its metadata and drop the bodies with
    `cf-aig-collect-log-payload: false`. Setting this false opts the whole
    gateway out. Zero Data Retention does not.
  EOT
}

variable "log_storage" {
  type = object({
    max_logs  = optional(number, 10000000)
    when_full = optional(string, "DELETE_OLDEST")
  })
  default     = {}
  nullable    = false
  description = <<-EOT
    How many logs the gateway keeps, and what happens at that count. Sent even
    when collect_logs is false, because the API stores it either way.

    - `max_logs`  - (Optional, default 10000000) 10000 to 10000000. Workers Paid
                    allows up to 10000000 per gateway; Workers Free allows
                    100000 across the whole account.
    - `when_full` - (Optional, default "DELETE_OLDEST") DELETE_OLDEST rotates, so
                    the gateway keeps the most recent max_logs. STOP_INSERTING
                    keeps the first max_logs and stops recording new requests,
                    which also stops Logpush exporting them. Requests are still
                    served either way.

    Both are sent explicitly: provider 5.23 turns an unset value into an
    explicit null on update, which resets the field
    (cloudflare/terraform-provider-cloudflare#7336). The defaults are what the
    API gives a gateway created without them.
  EOT

  validation {
    condition     = var.log_storage.max_logs >= 10000 && var.log_storage.max_logs <= 10000000 && floor(var.log_storage.max_logs) == var.log_storage.max_logs
    error_message = "log_storage.max_logs must be a whole number from 10000 to 10000000."
  }

  validation {
    condition     = contains(["DELETE_OLDEST", "STOP_INSERTING"], var.log_storage.when_full)
    error_message = "log_storage.when_full must be DELETE_OLDEST or STOP_INSERTING, in capitals."
  }
}

variable "cache" {
  type = object({
    ttl                  = number
    invalidate_on_update = optional(bool, false)
  })
  default     = null
  description = <<-EOT
    Response caching. Null leaves it off, which is Cloudflare's default.

    - `ttl`                  - Seconds a cached response is served for, greater
                               than zero. Cloudflare's ceiling is one month. The
                               API states no unit for this field; seconds is the
                               unit of the per-request cf-aig-cache-ttl header.
    - `invalidate_on_update` - (Optional, default false) Cloudflare does not
                               document this beyond its name. False is what the
                               dashboard sets.

    The cache key is the provider, endpoint, model, provider credential and the
    full request body. Every end user of an application that holds one provider
    key therefore shares one cache: the second person to send a byte-identical
    request gets the first person's answer, and the provider never sees it. Fine
    for a public FAQ bot, wrong for anything whose answer should depend on who
    asked. Only text and image responses are cached, streaming ones are not,
    and a client can bypass the cache with `cf-aig-skip-cache: true`.
  EOT

  validation {
    condition     = var.cache == null || try(var.cache.ttl > 0 && floor(var.cache.ttl) == var.cache.ttl, false)
    error_message = "cache.ttl must be a whole number of seconds greater than zero. To switch caching off, set cache = null rather than ttl = 0."
  }
}

variable "rate_limit" {
  type = object({
    limit     = number
    interval  = number
    technique = optional(string, "fixed")
  })
  default     = null
  description = <<-EOT
    Gateway-wide request rate limit. Null leaves it off.

    - `limit`     - Requests allowed per interval.
    - `interval`  - The window, in seconds.
    - `technique` - (Optional, default "fixed") fixed counts in clock-aligned
                    windows, so a burst either side of a boundary can reach twice
                    the limit. sliding counts the last `interval` seconds from
                    every request.

    One budget shared by every caller, not one per user - a route's `rate`
    element does per-user limits. A request over the limit gets 429 and never
    reaches the provider.
  EOT

  validation {
    condition = var.rate_limit == null || try(
      var.rate_limit.limit >= 1 && floor(var.rate_limit.limit) == var.rate_limit.limit &&
      var.rate_limit.interval >= 1 && floor(var.rate_limit.interval) == var.rate_limit.interval,
      false
    )
    error_message = "rate_limit.limit and rate_limit.interval must be whole numbers of at least 1. To switch rate limiting off, set rate_limit = null."
  }

  validation {
    condition     = var.rate_limit == null || contains(["fixed", "sliding"], try(var.rate_limit.technique, ""))
    error_message = "rate_limit.technique must be fixed or sliding."
  }
}

variable "retries" {
  type = object({
    max_attempts = number
    delay_ms     = number
    backoff      = string
  })
  default     = null
  description = <<-EOT
    Retry a request the provider failed, from the gateway, before the client
    sees the failure. Null leaves it off. All three are required once set, so
    the API is never left to fill one in.

    - `max_attempts` - 1 to 5.
    - `delay_ms`     - Base delay between attempts, 0 to 5000 milliseconds. The
                       API now accepts up to 60000; provider 5.23 does not.
    - `backoff`      - constant | linear | exponential.

    A client can override all three per request. A failed request can still
    have been billed, so a retried one can be billed more than once.
  EOT

  validation {
    condition     = var.retries == null || try(var.retries.max_attempts >= 1 && var.retries.max_attempts <= 5 && floor(var.retries.max_attempts) == var.retries.max_attempts, false)
    error_message = "retries.max_attempts must be a whole number from 1 to 5."
  }

  validation {
    condition     = var.retries == null || try(var.retries.delay_ms >= 0 && var.retries.delay_ms <= 5000 && floor(var.retries.delay_ms) == var.retries.delay_ms, false)
    error_message = "retries.delay_ms must be a whole number of milliseconds from 0 to 5000 - provider 5.23's ceiling, below the API's."
  }

  validation {
    condition     = var.retries == null || contains(["constant", "linear", "exponential"], try(var.retries.backoff, ""))
    error_message = "retries.backoff must be one of: constant, linear, exponential."
  }
}

variable "zero_data_retention" {
  type        = bool
  default     = false
  description = <<-EOT
    Zero Data Retention (`zdr`). Sends Unified Billing traffic to provider
    endpoints that do not retain prompts or responses.

    Narrower than it sounds. It covers only requests paid for with Cloudflare's
    Unified Billing credits - not BYOK, not a caller's own key - and only
    OpenAI and Anthropic; anything else falls back to the ordinary endpoint.
    It does not stop this gateway logging: that is collect_logs. Needs
    authentication on.
  EOT
}

variable "logpush_public_key" {
  type        = string
  default     = null
  description = <<-EOT
    Turns on Logpush for this gateway, encrypted to this key. Null leaves it
    off.

    The PUBLIC half of an RSA key pair, PEM, 16 to 1024 characters. Each log's
    request, response and metadata are encrypted to it, and only the private
    key decrypts them. That private key must never be in a tfvars file; the
    plan refuses anything that looks like one.

    Only the gateway's half. Logs are not exported until a Logpush job for the
    AI Gateway dataset also exists, and provider 5.23 has no dataset value for
    it, so that job is made in the dashboard. Needs collect_logs, and Workers
    Paid. When log storage is full and when_full is STOP_INSERTING, exports
    stop too.
  EOT

  validation {
    condition     = var.logpush_public_key == null || try(length(var.logpush_public_key) >= 16 && length(var.logpush_public_key) <= 1024, false)
    error_message = "logpush_public_key must be 16 to 1024 characters."
  }

  validation {
    condition     = var.logpush_public_key == null || !strcontains(upper(coalesce(var.logpush_public_key, "-")), "PRIVATE KEY")
    error_message = "logpush_public_key looks like a PRIVATE key. Only the public half belongs here. Treat that private key as exposed - it has been in a file, and possibly in git history - and generate a new pair."
  }
}

variable "secrets_store_id" {
  type        = string
  default     = null
  description = <<-EOT
    The Secrets Store holding this gateway's BYOK provider keys (`store_id`).
    Null for a gateway whose callers send their own provider key, or pay with
    Unified Billing credits.

    Linking the store is all this does. The keys, which must be named
    <gateway_id>_<provider>_<alias>, and the provider configs that attach them,
    are made outside Terraform: provider 5.23 has no resource for either
    (cloudflare/terraform-provider-cloudflare#7332).

    An adopted gateway that already uses BYOK must set this. Otherwise the first
    apply unlinks its store - null is sent as "", which is how the API reports
    an unset store - and the plan shows it only as store_id changing to "".
    Needs authentication on.
  EOT

  validation {
    condition     = var.secrets_store_id == null || can(regex("^[A-Za-z0-9]+$", coalesce(var.secrets_store_id, "-")))
    error_message = "secrets_store_id must be the store's ID from the Secrets Store dashboard: letters and digits only."
  }
}

variable "dlp_policies" {
  type = map(object({
    action   = string
    check    = list(string)
    profiles = list(string)
    enabled  = optional(bool, true)
  }))
  default     = {}
  description = <<-EOT
    Data Loss Prevention, keyed by policy ID. Empty leaves DLP off.

    - `action`   - FLAG records the match in the log and a `cf-aig-dlp` response
                   header and lets the request through. BLOCK refuses it:
                   error 2029 for a blocked prompt, 2030 for a blocked response.
    - `check`    - ["REQUEST"], ["RESPONSE"] or both. REQUEST stops data
                   reaching the provider; RESPONSE stops a model handing it back.
    - `profiles` - Zero Trust DLP profile UUIDs, from the DLP section of the
                   Zero Trust dashboard. There is no data source that resolves
                   one by name.
    - `enabled`  - (Optional, default true)

    The key is sent as the policy's ID: letters, digits, underscores, hyphens.

    Profiles are account-wide, so editing one changes every gateway and Gateway
    policy that uses it. Without a Zero Trust subscription only two predefined
    profiles exist. Scanning responses buffers a streamed reply, and a response
    already cached is served without being rescanned after a policy changes.

    Cloudflare's create call does not take DLP - see main.tf.
  EOT

  validation {
    condition     = alltrue([for id in keys(var.dlp_policies) : can(regex("^[A-Za-z0-9_-]+$", id))])
    error_message = "dlp_policies keys are sent as policy IDs and must be letters, digits, underscores and hyphens."
  }

  validation {
    condition     = alltrue([for policy in var.dlp_policies : contains(["FLAG", "BLOCK"], policy.action)])
    error_message = "dlp_policies[*].action must be FLAG or BLOCK, in capitals."
  }

  validation {
    condition = alltrue([
      for policy in var.dlp_policies :
      length(policy.check) > 0 && length(distinct(policy.check)) == length(policy.check) && alltrue([for side in policy.check : contains(["REQUEST", "RESPONSE"], side)])
    ])
    error_message = "dlp_policies[*].check must list REQUEST, RESPONSE or both, each at most once, in capitals."
  }

  validation {
    condition = alltrue([
      for policy in var.dlp_policies :
      length(policy.profiles) > 0 && alltrue([
        for id in policy.profiles : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
      ])
    ])
    error_message = "dlp_policies[*].profiles must list at least one DLP profile UUID, copied from the DLP section of the Zero Trust dashboard. A policy with no profile matches nothing."
  }
}

variable "guardrails" {
  type = object({
    prompt   = optional(map(string), {})
    response = optional(map(string), {})
  })
  default     = null
  description = <<-EOT
    Content safety checks on prompts and responses: category => FLAG | BLOCK.
    A category left out is not acted on. Null leaves guardrails off.

      violent_crimes             S1     specialized_advice      S6
      non_violent_crimes         S2     privacy                 S7
      sex_related_crimes         S3     intellectual_property   S8
      child_sexual_exploitation  S4     indiscriminate_weapons  S9
      defamation                 S5     hate                    S10
      suicide_and_self_harm      S11    sexual_content          S12
      elections                  S13    prompt_injection        P1

    S1-S13 are Llama Guard 3 categories, P1 is Prompt Guard. Both run on Workers
    AI and are billed as Workers AI inference, adding roughly half a second to
    every request.

    FLAG only records the match. BLOCK refuses the request (error 2016 for a
    prompt, 2017 for a response) - and if any category is BLOCK and Workers AI
    cannot be reached, every request is refused. A streamed response is either
    buffered and returned whole, or, through the REST API, logged but not
    enforced.

    Cloudflare's create call does not take guardrails - see main.tf.
  EOT

  validation {
    # Duplicated from local.guardrail_codes, because validation cannot read a local.
    condition = var.guardrails == null || alltrue([
      for name in concat(keys(try(var.guardrails.prompt, {})), keys(try(var.guardrails.response, {}))) :
      contains([
        "violent_crimes", "non_violent_crimes", "sex_related_crimes", "child_sexual_exploitation",
        "defamation", "specialized_advice", "privacy", "intellectual_property",
        "indiscriminate_weapons", "hate", "suicide_and_self_harm", "sexual_content",
        "elections", "prompt_injection",
      ], name)
    ])
    error_message = "guardrails categories must be from: violent_crimes, non_violent_crimes, sex_related_crimes, child_sexual_exploitation, defamation, specialized_advice, privacy, intellectual_property, indiscriminate_weapons, hate, suicide_and_self_harm, sexual_content, elections, prompt_injection."
  }

  validation {
    condition = var.guardrails == null || alltrue([
      for action in concat(values(try(var.guardrails.prompt, {})), values(try(var.guardrails.response, {}))) :
      contains(["FLAG", "BLOCK"], action)
    ])
    error_message = "guardrails actions must be FLAG or BLOCK, in capitals. Leave a category out rather than trying to set it to ignore - the API has no such value."
  }

  validation {
    condition     = var.guardrails == null || length(try(var.guardrails.prompt, {})) + length(try(var.guardrails.response, {})) > 0
    error_message = "guardrails sets no category on either side, which checks nothing while still looking configured. Set guardrails = null to leave them off."
  }
}

variable "spend_limits" {
  type = map(object({
    limit            = number
    window           = number
    technique        = optional(string, "sliding")
    enabled          = optional(bool, true)
    models           = optional(list(string), [])
    providers        = optional(list(string), [])
    partition_by     = optional(list(string), [])
    metadata_filters = optional(map(list(string)), {})
  }))
  default     = {}
  description = <<-EOT
    Cost budgets, keyed by rule ID. Once the spend a rule counts reaches its
    limit within its window, the gateway answers 429 until the window resets.
    Empty leaves spend limits off.

    - `limit`            - US dollars, greater than zero.
    - `window`           - A whole number greater than zero. CLOUDFLARE DOES NOT
                           DOCUMENT ITS UNIT. The dashboard offers daily, weekly
                           and monthly windows: create one rule there, read it
                           back with GET /accounts/<id>/ai-gateway/gateways/<id>,
                           and copy the number it shows rather than assuming
                           seconds.
    - `technique`        - (Optional, default "sliding") sliding is a rolling
                           window; fixed resets at midnight, on Monday or on the
                           first of the month.
    - `enabled`          - (Optional, default true)
    - `models`           - (Optional) Count only requests for these models.
    - `providers`        - (Optional) Count only requests to these providers.
    - `partition_by`     - (Optional) Custom metadata keys (from the
                           `cf-aig-metadata` header) that split the budget: one
                           budget per distinct value, e.g. ["user_id"].
                           `cf.user_id` is the Cloudflare Access user.
    - `metadata_filters` - (Optional) Metadata key => values. Count only requests
                           whose key holds one of them.
    A dimension left empty means every value shares one budget.

    The key is sent as the rule ID: letters, digits, underscores, hyphens. When
    adopting a gateway, use each existing rule's ID as its key, or the apply
    replaces the rule.

    Spend is estimated from token counts and Cloudflare's pricing for the
    model, recorded after each request completes. A burst can overshoot before
    the block lands, and a request whose model has no known price is not
    counted. It covers what the gateway pays for - Unified Billing and BYOK -
    and at most 20 rules. Cloudflare's create call does not take spend limits -
    see main.tf.
  EOT

  validation {
    condition     = length(var.spend_limits) <= 20
    error_message = "spend_limits holds more than 20 rules. Cloudflare allows 20 per gateway and refuses the rest at apply."
  }

  validation {
    condition     = alltrue([for id in keys(var.spend_limits) : can(regex("^[A-Za-z0-9_-]+$", id))])
    error_message = "spend_limits keys are sent as rule IDs and must be letters, digits, underscores and hyphens."
  }

  validation {
    condition = alltrue([
      for rule in var.spend_limits :
      rule.limit > 0 && rule.window > 0 && floor(rule.window) == rule.window
    ])
    error_message = "spend_limits[*].limit must be greater than zero dollars, and window a whole number greater than zero."
  }

  validation {
    condition     = alltrue([for rule in var.spend_limits : contains(["fixed", "sliding"], rule.technique)])
    error_message = "spend_limits[*].technique must be fixed or sliding."
  }

  validation {
    condition = alltrue([
      for rule in var.spend_limits :
      length(setintersection(toset(rule.partition_by), toset(keys(rule.metadata_filters)))) == 0
    ])
    error_message = "A metadata key cannot be in both partition_by and metadata_filters of the same rule - the API takes one mode per key."
  }

  validation {
    condition     = alltrue([for rule in var.spend_limits : alltrue([for values in values(rule.metadata_filters) : length(values) > 0])])
    error_message = "Every spend_limits[*].metadata_filters entry must list at least one value. A filter with no values matches nothing."
  }
}

variable "routes" {
  type = map(object({
    elements = map(object({
      type       = string
      outputs    = optional(map(string), {})
      conditions = optional(string)
      key        = optional(string)
      limit      = optional(number)
      limit_type = optional(string)
      window     = optional(number)
      provider   = optional(string)
      model      = optional(string)
      retries    = optional(number)
      timeout    = optional(number)
    }))
  }))
  default     = {}
  description = <<-EOT
    Dynamic routes, keyed by route name. A client uses one by sending
    `"model": "dynamic/<name>"` to the gateway's OpenAI-compatible endpoint;
    the other endpoints do not route. Renaming a route breaks every client that
    names it.

    A route is a graph of elements, keyed by element ID. Each element's
    `outputs` maps an output name to the ID of the element that runs next.

      start        outputs: next                  One per route. Runs first.
      conditional  outputs: true, false           conditions = jsonencode({...}):
                                                  $eq, $ne, $in, $and, $or over
                                                  the body, headers or metadata,
                                                  e.g. { "metadata.plan" = { "$eq" = "free" } }
      rate         outputs: success, [fallback]   key (e.g. "metadata.user_id"),
                                                  limit, limit_type (count | cost),
                                                  window (seconds). Per-value limit,
                                                  unlike the gateway's rate_limit.
      model        outputs: success, [fallback]   provider, model, retries,
                                                  timeout (milliseconds).
      end          (none)                         Returns the last successful model
                                                  response, or an error.

    fallback is optional; without it a rate-limited or failed request ends the
    route with an error. Percentage splits are not supported: their outputs are
    keyed by share ("10%"), which provider 5.23 cannot represent. Build a route
    that needs one in the dashboard, outside this module.

    Changing any element replaces the route - see main.tf. Routes need
    authentication on, and Cloudflare's docs expect the providers they call to
    have BYOK keys stored on the gateway.
  EOT

  validation {
    condition     = alltrue([for name in keys(var.routes) : name != "" && trimspace(name) == name && !strcontains(name, "/")])
    error_message = "routes keys are route names, sent by clients as \"dynamic/<name>\": not empty, no leading or trailing spaces, and no \"/\"."
  }

  validation {
    condition = alltrue(flatten([
      for route in var.routes : [for id in keys(route.elements) : can(regex("^[A-Za-z0-9_-]+$", id))]
    ]))
    error_message = "Element IDs (the keys of routes[*].elements) must be letters, digits, underscores and hyphens."
  }

  validation {
    condition = alltrue(flatten([
      for route in var.routes : [for element in route.elements : contains(["start", "conditional", "rate", "model", "end"], element.type)]
    ]))
    error_message = "Element type must be one of: start, conditional, rate, model, end. A percentage split cannot be managed here - its outputs are keyed by share, which provider 5.23 cannot represent. Build that route in the dashboard."
  }

  validation {
    # Which outputs each type takes, and which of them it must have.
    condition = alltrue(flatten([
      for route in var.routes : [
        for element in route.elements : (
          element.type == "start" ? toset(keys(element.outputs)) == toset(["next"]) :
          element.type == "conditional" ? toset(keys(element.outputs)) == toset(["true", "false"]) :
          element.type == "end" ? length(element.outputs) == 0 :
          contains(keys(element.outputs), "success") && length(setsubtract(toset(keys(element.outputs)), toset(["success", "fallback"]))) == 0
        )
      ]
    ]))
    error_message = "Element outputs do not match their type: start takes exactly `next`; conditional exactly `true` and `false`; rate and model take `success` and optionally `fallback`; end takes none."
  }

  validation {
    condition = alltrue(flatten([
      for route in var.routes : [
        for element in route.elements :
        element.type != "conditional" || try(length(keys(jsondecode(element.conditions))) > 0, false)
      ]
    ]))
    error_message = "A conditional element needs `conditions`: a JSON object, written as jsonencode({ ... }), with at least one condition."
  }

  validation {
    condition = alltrue(flatten([
      for route in var.routes : [
        for element in route.elements :
        element.type != "rate" || (
          try(trimspace(element.key) != "", false) &&
          try(element.limit > 0, false) &&
          contains(["count", "cost"], coalesce(element.limit_type, "-")) &&
          try(element.window > 0, false)
        )
      ]
    ]))
    error_message = "A rate element needs key (the request field to count by, e.g. \"metadata.user_id\"), limit greater than zero, limit_type count or cost, and window in seconds greater than zero."
  }

  validation {
    condition = alltrue(flatten([
      for route in var.routes : [
        for element in route.elements :
        element.type != "model" || (
          try(trimspace(element.provider) != "", false) &&
          try(trimspace(element.model) != "", false) &&
          try(element.retries >= 0 && floor(element.retries) == element.retries, false) &&
          try(element.timeout > 0, false)
        )
      ]
    ]))
    error_message = "A model element needs provider (e.g. \"openai\"), model, retries (a whole number, 0 for none) and timeout in milliseconds greater than zero. All four are required by the API."
  }

  validation {
    # A property on the wrong element type is dropped or refused, and either
    # way it reads as configured when it is not.
    condition = alltrue(flatten([
      for route in var.routes : [
        for element in route.elements : (
          (element.type == "conditional" || element.conditions == null) &&
          (element.type == "rate" || (element.key == null && element.limit == null && element.limit_type == null && element.window == null)) &&
          (element.type == "model" || (element.provider == null && element.model == null && element.retries == null && element.timeout == null))
        )
      ]
    ]))
    error_message = "An element sets a property its type does not take. conditions belongs to conditional; key, limit, limit_type and window to rate; provider, model, retries and timeout to model. start and end take none."
  }
}
