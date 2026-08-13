# Layer gateway - inputs.
#
# Two config sources feed it:
#   accounts/<account>/account.tfvars   the account ID
#   accounts/<account>/gateway.tfvars   everything below

variable "cloudflare_account_id" {
  type        = string
  description = <<-EOT
    Cloudflare Account ID this layer run targets. Supplied from
    accounts/<account>/account.tfvars, or overridden with
    TF_VAR_cloudflare_account_id.
  EOT

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "gateway_policies" {
  description = <<-EOT
    Gateway policies for this account, keyed by a logical key.

    The key is a handle and renaming it destroys and recreates the policy - which
    for a block is a moment with the rule absent, and for an allow is a moment
    with it present. The `name` is what the dashboard and the Gateway logs show.

    - `name`              - Display name in the Zero Trust dashboard.
    - `type`              - "dns", "network" or "http". Three separate enforcement
                            pipelines, not three sections of one list:
                              dns     - answered before a connection exists. Cheapest
                                        to enforce, and blind to anything past the
                                        hostname. Also the one a device using
                                        DNS-over-HTTPS to a third party can sidestep,
                                        which is why the same block is usually worth
                                        repeating at http.
                              network - the L4 connection: ports, protocols, IPs and
                                        the TLS SNI. No visibility into the payload.
                              http    - the decrypted L7 request. The only place a DLP
                                        profile, an upload or a URL can be matched.
    - `action`            - What Gateway does with a match:
                              dns     : allow, block, override, safesearch, ytrestricted
                              network : allow, block, l4_override
                              http    : allow, block, off, on, scan, noscan, isolate,
                                        noisolate, quarantine, redirect
                            "off" is Do Not Inspect - the connection is passed through
                            undecrypted. It is how a Microsoft 365 bypass is written.
    - `precedence`        - Evaluation order within this policy's type. Lower runs
                            first and Gateway stops at the first allow or block it
                            matches, so this is the whole of the rule ordering.
                            Precedences below var.reserved_precedence_ceiling are
                            reserved for the platform baseline and refused here.
                            Leave gaps - steps of 100 - so a rule can be inserted
                            later without renumbering the ones after it.
    - `description`       - (Optional) Shown in the dashboard and the audit log.
    - `enabled`           - (Optional) Deploy the policy but leave it inactive.
    - `match_all_traffic` - (Optional) This policy deliberately names no selector and
                            matches everything of its type. Required for a catch-all,
                            and refused for allow, off, noscan and noisolate - Gateway
                            stops at the first match, so an unscoped allow deletes
                            every policy below it.

    MATCHING

    `match` names selectors; the layer compiles them into a Cloudflare wirefilter
    expression, so no account tree contains one. The compiled shape is:

      ( destination terms OR'd ) and ( each remaining constraint AND'd )

    Destination terms - alternative ways of naming the same thing:

      domains               - the domain and all its subdomains. dns and http
      hosts                 - one exact hostname. dns and http
      sni_domains           - the same, read from the TLS SNI. network
      sni_hosts             - one exact SNI. network
      applications          - Cloudflare application NAMES, for example "Microsoft 365".
                              Resolved against the account's application catalogue at
                              plan time. One application covers every hostname
                              Cloudflare knows it uses
      content_categories    - Cloudflare content category NAMES
      security_categories   - Cloudflare security category NAMES, for example
                              "Command and Control & Botnet" and "Malware"
      destination_ip_cidrs  - destination ranges. On a dns policy this is the RESOLVED
                              address, so it is evaluated after the answer comes back

    Constraints - each is OR'd internally and AND'd against the rest:

      source_ip_cidrs       - where the request came from
      destination_ports     - network only
      protocols             - network only. "tcp", "udp" or "icmp"
      http_methods          - http only
      dlp_profile_ids       - http only. DLP profile UUIDs from the dashboard. A match
                              means the request body contained what the profile
                              describes
      upload_file_types     - http only. OR'd with download_file_types
      download_file_types   - http only

      negate                - invert the whole expression, for a default-deny rule
                              with an allowed list carved out

    `identity` restricts to people rather than traffic, and its terms are OR'd:
    `user_emails`, `user_group_names`, `user_group_emails`, `user_group_ids`.
    Group names are the ones the identity provider sends, which for Entra ID means
    the group's display name and needs `support_groups` on the provider in the
    zerotrust layer.

    `device_posture_check_ids` restricts to devices that PASSED the named WARP
    posture checks.

    `traffic_expression`, `identity_expression` and `device_posture_expression`
    take a raw wirefilter expression for a selector this layer does not model.
    They replace the compiled expression for that dimension rather than adding to
    it, and no guardrail can see inside one.

    SCHEDULING AND EXPIRY

    `schedule` restricts the policy to time windows, per day, in a named IANA time
    zone: `{ time_zone = "Europe/London", mon = "08:00-18:00" }`. A day left unset
    means the policy does not apply that day at all.

    `expiration` switches the policy off at a timestamp. Useful for a temporary
    exception, and a trap for anything else: nothing warns you the day it lapses.

    SETTINGS

    `settings` carries the parts of Cloudflare's rule_settings a gateway actually
    uses. Each is only accepted where Cloudflare honours it, and the plan says so
    if it is put somewhere else:

      block_reason                       - recorded and shown for a block
      block_page_enabled                 - Cloudflare's block page. dns block
      block_page                         - your own page instead. http block
      notification                       - the WARP client notification for a block
      redirect                           - required by action = "redirect"
      check_session                      - re-authentication interval. http, network
      l4_override                        - required by action = "l4_override"
      untrusted_cert_action              - what to do when the origin certificate does
                                           not validate. http
      payload_log_enabled                - store the matched content of a DLP hit.
                                           Governed by allow_dlp_payload_logging
      quarantine_file_types              - required by action = "quarantine"
      override_host / override_ips       - required by action = "override". dns
      insecure_disable_dnssec_validation - dns. Governed by
                                           allow_disabling_dnssec_validation
      ip_categories                      - category filtering for IP literals. dns
      ignore_cname_category_matches      - dns
  EOT
  type = map(object({
    name              = string
    type              = string
    action            = string
    precedence        = number
    description       = optional(string)
    enabled           = optional(bool, true)
    match_all_traffic = optional(bool, false)

    match = optional(object({
      negate               = optional(bool, false)
      domains              = optional(list(string), [])
      hosts                = optional(list(string), [])
      sni_domains          = optional(list(string), [])
      sni_hosts            = optional(list(string), [])
      applications         = optional(list(string), [])
      content_categories   = optional(list(string), [])
      security_categories  = optional(list(string), [])
      destination_ip_cidrs = optional(list(string), [])
      source_ip_cidrs      = optional(list(string), [])
      destination_ports    = optional(list(number), [])
      protocols            = optional(list(string), [])
      http_methods         = optional(list(string), [])
      dlp_profile_ids      = optional(list(string), [])
      upload_file_types    = optional(list(string), [])
      download_file_types  = optional(list(string), [])
    }), {})

    identity = optional(object({
      user_emails       = optional(list(string), [])
      user_group_names  = optional(list(string), [])
      user_group_emails = optional(list(string), [])
      user_group_ids    = optional(list(string), [])
    }), {})

    device_posture_check_ids = optional(list(string), [])

    traffic_expression        = optional(string)
    identity_expression       = optional(string)
    device_posture_expression = optional(string)

    schedule = optional(object({
      time_zone = optional(string)
      mon       = optional(string)
      tue       = optional(string)
      wed       = optional(string)
      thu       = optional(string)
      fri       = optional(string)
      sat       = optional(string)
      sun       = optional(string)
    }))

    expiration = optional(object({
      expires_at = string
      duration   = optional(number)
    }))

    settings = optional(object({
      block_reason       = optional(string)
      block_page_enabled = optional(bool)
      block_page = optional(object({
        target_uri      = string
        include_context = optional(bool)
      }))
      notification = optional(object({
        enabled         = optional(bool)
        msg             = optional(string)
        support_url     = optional(string)
        include_context = optional(bool)
      }))
      redirect = optional(object({
        target_uri              = string
        include_context         = optional(bool)
        preserve_path_and_query = optional(bool)
      }))
      check_session = optional(object({
        duration = optional(string)
        enforce  = optional(bool)
      }))
      l4_override = optional(object({
        ip   = string
        port = optional(number)
      }))
      untrusted_cert_action              = optional(string)
      payload_log_enabled                = optional(bool)
      quarantine_file_types              = optional(list(string))
      override_host                      = optional(string)
      override_ips                       = optional(list(string))
      insecure_disable_dnssec_validation = optional(bool)
      ip_categories                      = optional(bool)
      ignore_cname_category_matches      = optional(bool)
    }), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.gateway_policies) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "gateway_policies keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
  }

  validation {
    condition = length(distinct([
      for policy in var.gateway_policies : lower(trimspace(policy.name))
    ])) == length(var.gateway_policies)
    error_message = "Two gateway_policies entries share a name. The name identifies the policy in the dashboard and in Gateway's logs, so each must be uniquely named."
  }

  validation {
    condition     = alltrue([for policy in var.gateway_policies : contains(["dns", "network", "http"], policy.type)])
    error_message = "Each gateway_policies[*].type must be \"dns\", \"network\" or \"http\". Egress and resolver policies are separate Gateway builders with their own actions and are not managed by this layer."
  }
}

variable "gateway_baseline_policies" {
  type        = list(string)
  default     = []
  description = <<-EOT
    Platform baseline policies this account opts into, by name. The catalogue is
    in layers/gateway/locals.gateway.tf and is customer-agnostic: every value it
    depends on comes from a variable, so the same rule serves every account.

      block_security_threats       dns  block       Cloudflare's security categories.
                                                    Needs gateway_security_categories.
      block_security_threats_http  http block       The same categories again at L7.
                                                    Needs gateway_security_categories.
      block_disallowed_content     dns  block       Content categories the account does
                                                    not permit. Needs
                                                    gateway_blocked_content_categories.
      bypass_trusted_applications  http off         Do Not Inspect for named
                                                    applications. Needs
                                                    gateway_bypass_applications.
      block_dlp_matches            http block       Requests whose body matches a DLP
                                                    profile. Needs
                                                    gateway_dlp_profile_ids.
      quarantine_risky_downloads   http quarantine  Executable downloads to the file
                                                    sandbox. Needs
                                                    gateway_quarantine_file_types.

    block_security_threats_http exists because DNS filtering is not a control a
    determined client has to cooperate with: a browser resolving over
    DNS-over-HTTPS to a resolver that is not Gateway never asks the DNS policy.
    The HTTP policy sees the connection regardless.

    Selecting a baseline whose parameter list is empty fails the plan. That is
    not tidiness: an empty set renders as `in {}`, which Cloudflare rejects as a
    syntax error, and a bypass rule with no applications in it would be a Do Not
    Inspect policy matching nothing while the dashboard shows it as configured.

    Baseline policies occupy the precedence band below
    var.reserved_precedence_ceiling, so they evaluate before anything an account
    tree adds and an account tree cannot get in front of them.
  EOT

  validation {
    condition = alltrue([
      for name in var.gateway_baseline_policies : contains([
        "block_security_threats", "block_security_threats_http",
        "block_disallowed_content", "bypass_trusted_applications",
        "block_dlp_matches", "quarantine_risky_downloads",
      ], name)
    ])
    error_message = "gateway_baseline_policies must name entries from the catalogue in layers/gateway/locals.gateway.tf: block_security_threats, block_security_threats_http, block_disallowed_content, bypass_trusted_applications, block_dlp_matches, quarantine_risky_downloads."
  }

  validation {
    condition     = length(distinct(var.gateway_baseline_policies)) == length(var.gateway_baseline_policies)
    error_message = "gateway_baseline_policies names the same baseline twice."
  }
}

variable "gateway_security_categories" {
  type        = list(string)
  default     = []
  description = <<-EOT
    Cloudflare security category names the baseline threat rules block, for
    example ["Command and Control & Botnet", "Malware"]. Names are resolved
    against the account's category catalogue at plan time, and an unrecognised
    one fails the plan listing what Cloudflare actually offers.

    Security categories describe intent - a domain used to run malware, phish
    credentials or exfiltrate data - rather than subject matter. They are the ones
    worth blocking everywhere, because nothing legitimate is lost by it.

    Whether a given name belongs here or in gateway_blocked_content_categories
    follows Cloudflare's own grouping in the dashboard. Cloudflare's category API
    does not distinguish the two, so a content category named here is resolved to
    a valid ID and then matched against the security category field, where it
    never matches. The rule would look configured and do nothing.
  EOT
}

variable "gateway_blocked_content_categories" {
  type        = list(string)
  default     = []
  description = <<-EOT
    Cloudflare content category names the baseline content rule blocks. Content
    categories describe subject matter rather than intent, so this is an
    acceptable-use decision for the account rather than a security one, and it is
    empty by default because there is no answer that suits every customer.
  EOT
}

variable "gateway_bypass_applications" {
  type        = list(string)
  default     = []
  description = <<-EOT
    Cloudflare application names the baseline bypass rule exempts from TLS
    inspection, for example ["Microsoft 365"]. Names are resolved against the
    account's application catalogue at plan time.

    Bypassing an application means Gateway stops decrypting it, so nothing inside
    it is inspected, logged in detail or matched by a DLP profile from that point
    on. It is done for Microsoft 365 because certificate pinning and client-side
    TLS behaviour break under inspection, not because the traffic is uninteresting
    - a bypassed application is a channel data can leave through unexamined.

    Keep the list to applications that genuinely cannot be inspected, and prefer
    naming the application to naming its hostnames: Cloudflare maintains the
    hostname list, and a hostname added by Microsoft next month is covered without
    a pull request.
  EOT
}

variable "gateway_dlp_profile_ids" {
  type        = list(string)
  default     = []
  description = <<-EOT
    DLP profile UUIDs the baseline DLP rule blocks on. Data Loss Prevention
    profiles are defined in the Zero Trust dashboard under DLP, and Cloudflare
    exposes no data source that resolves one by name, so these arrive as IDs
    rather than names - the one place in this layer where an opaque identifier is
    unavoidable.

    A DLP match is produced by scanning the decrypted request body, so it works
    only on HTTP policies and only where the traffic is actually inspected.
    Anything covered by gateway_bypass_applications is not.
  EOT

  validation {
    condition = alltrue([
      for id in var.gateway_dlp_profile_ids :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ])
    error_message = "Each gateway_dlp_profile_ids entry must be a UUID, copied from the DLP profile in the Zero Trust dashboard."
  }
}

variable "gateway_quarantine_file_types" {
  type        = list(string)
  default     = []
  description = <<-EOT
    File types the baseline quarantine rule sends to Cloudflare's file sandbox
    rather than delivering, for example ["exe", "zip", "rar"].

    Quarantine holds the download while it is detonated and scanned, so the user
    waits. That is tolerable for executables and archives and unreasonable for
    anything people fetch all day, which is why this is a short list rather than
    a broad one.

    Cloudflare's sandbox accepts a fixed set of formats, and it is shorter than
    the set a policy can match on - "dll" and "scr" are both rejected.
  EOT

  validation {
    condition = alltrue([
      for file_type in var.gateway_quarantine_file_types : contains([
        "exe", "pdf", "doc", "docm", "docx", "rtf", "ppt", "pptx", "xls",
        "xlsm", "xlsx", "zip", "rar",
      ], lower(trimspace(file_type)))
    ])
    error_message = "Each gateway_quarantine_file_types entry must be one Cloudflare's file sandbox accepts: exe, pdf, doc, docm, docx, rtf, ppt, pptx, xls, xlsm, xlsx, zip, rar."
  }
}

# Platform defaults (defaults.auto.tfvars)
variable "reserved_precedence_ceiling" {
  type        = number
  default     = 100
  description = <<-EOT
    Precedence values below this are reserved for the platform baseline. An
    account tree policy asking for one fails the plan.

    Gateway evaluates a builder in ascending precedence and stops at the first
    allow or block that matches, so "the platform rules come first" is not a
    convention that can be documented and hoped for - it is a number, and without
    a floor an account tree could put an allow in front of the baseline block and
    nothing would report it.
  EOT

  validation {
    condition     = var.reserved_precedence_ceiling > 0
    error_message = "reserved_precedence_ceiling must be greater than zero."
  }
}

variable "restricted_actions" {
  type        = list(string)
  default     = []
  description = <<-EOT
    Gateway actions this layer refuses to create. The plan fails naming the
    policy and the action.

    Empty by default, because the action worth thinking hardest about - "off",
    Do Not Inspect - is also the one a Microsoft 365 deployment cannot do without.
    An account that has decided inspection is never to be turned off outside the
    baseline sets ["off"] here, and the baseline bypass then has to be justified
    as a change to this list rather than as a line in an account tree.

    "noscan" and "noisolate" are the other two candidates: both remove a control
    for traffic that would otherwise have had it.
  EOT

  validation {
    condition = alltrue([
      for action in var.restricted_actions : contains([
        "allow", "block", "off", "on", "scan", "noscan", "isolate", "noisolate",
        "quarantine", "redirect", "override", "safesearch", "ytrestricted",
        "l4_override",
      ], action)
    ])
    error_message = "Each restricted_actions entry must be a Gateway action: allow, block, off, on, scan, noscan, isolate, noisolate, quarantine, redirect, override, safesearch, ytrestricted, l4_override."
  }
}

variable "allow_dlp_payload_logging" {
  type        = bool
  default     = false
  description = <<-EOT
    Permit a policy to set settings.payload_log_enabled.

    DLP payload logging writes the fragment of the request that triggered the
    match into Cloudflare's logs. That fragment is by definition the sensitive
    data the policy exists to protect - the card number, the national insurance
    number, the private key - and it is then readable by everybody with Gateway
    log access, and retained on Cloudflare's terms rather than yours.

    It is genuinely useful for tuning a profile that is firing too often, and it
    is not something to leave on afterwards. Turning it on is a pull request that
    says which investigation it is for; turning it off again is the next one.
  EOT
}

variable "allow_disabling_dnssec_validation" {
  type        = bool
  default     = false
  description = <<-EOT
    Permit a policy to set settings.insecure_disable_dnssec_validation.

    DNSSEC validation is what stops a forged answer being accepted for a signed
    zone. Turning it off for a policy makes that policy's resolution
    spoofable, and the usual reason somebody wants to is an internal zone that is
    signed badly - which is a problem to fix at the zone rather than to work
    around at the resolver.
  EOT
}

variable "allow_untrusted_certificate_pass_through" {
  type        = bool
  default     = false
  description = <<-EOT
    Permit settings.untrusted_cert_action = "pass_through", which serves a site
    whose certificate did not validate as though nothing was wrong.

    The user sees no warning, and neither does anybody reading the logs. An
    expired certificate on an internal service is the common cause and a
    machine-in-the-middle is the one that matters, and pass_through cannot tell
    them apart. "error" and "block" both leave a trail.
  EOT
}

variable "default_untrusted_cert_action" {
  type        = string
  default     = "error"
  description = <<-EOT
    What an HTTP allow policy does about an origin certificate that does not
    validate, when the policy sets nothing of its own. "error" shows the user
    Cloudflare's error page, "block" applies the block page and logs it as a
    block, "pass_through" serves the site anyway.

    Declared on every HTTP allow policy rather than left to Cloudflare's default,
    so a change made in the dashboard shows up as drift on the next plan.
  EOT

  validation {
    condition     = contains(["pass_through", "block", "error"], var.default_untrusted_cert_action)
    error_message = "default_untrusted_cert_action must be \"pass_through\", \"block\" or \"error\"."
  }
}

variable "default_block_notification" {
  type = object({
    enabled     = optional(bool, true)
    msg         = optional(string)
    support_url = optional(string)
  })
  default     = null
  description = <<-EOT
    The WARP client notification shown when a policy blocks something, applied to
    every block policy that sets no notification of its own.

    Worth setting, and worth setting with a support URL. The alternative to
    telling somebody why their request failed and where to ask about it is a
    ticket that says "the internet is broken", and a user who concludes the
    corporate network cannot be used for a legitimate task and finds another one.
  EOT
}
