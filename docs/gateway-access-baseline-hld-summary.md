# Cloudflare Landing Zone: Gateway and Access baseline (source material for HLD)

Summary of the Cloudflare One Gateway (Secure Web Gateway) and Access rules as implemented, for use when filling in the Zero Trust / SSE section of a High-Level Design. Written from the code at `main` @ `4ae43c7` on 2026-10-27. Where this document and the code disagree, the code wins.

**Source of truth:**

- Gateway layer: `deployment/layers/gateway/`
  - Baseline catalogue: `locals.gateway.tf`
  - Assembly and name resolution: `locals.tf`, `catalogue_lookup.tf`
  - Guards: `preflight.tf`
  - Platform defaults: `defaults.auto.tfvars`
- Gateway module: `modules/gateway/`
  - Expression compiler and policy guards: `locals.tf`, `main.tf`
  - Account settings and inspection CA: `settings.tf`, `certificate.tf`, `locals.settings.tf`
- Access layer: `deployment/layers/zerotrust/`
  - Assembly: `locals.tf`
  - Guards: `preflight.tf`
  - Platform defaults: `defaults.auto.tfvars`
- Access module: `modules/zerotrust/`
- Per-account config: `deployment/accounts/<account>/gateway.tfvars` and `zerotrust.tfvars`

The account values in sections A6 and B6 are sample/placeholder data (RFC 5737 IPs, example.com, zeroed UUIDs).

## 0. What "baselined" means in each layer

The two layers are built differently, and the HLD should not describe them the same way.

- **Gateway has a rule catalogue.** Six platform policies are defined once in `locals.gateway.tf`. Each account opts in by name through `gateway_baseline_policies`. They sit in a reserved precedence band below 100, so account rules cannot get in front of them. Platform guardrails sit on top.
- **Access has no rule catalogue.** The platform baseline is the organisation-level defaults (session lengths, seat expiry, service token lifetime) and the plan-time guardrails (for example, `bypass` is refused). Every identity provider, group, policy and application comes from the account tree. The account_a sample is the de facto template.

# Part A: Gateway

## A1. Design model

- **One module instance per account.** Gateway is account-scoped, so no zone is involved.
- **Three builders are managed:** `dns`, `network` and `http`. Egress and resolver policies are separate Gateway builders and are rejected by input validation.
- **Policy set = selected baseline policies + account `gateway_policies`**, concatenated into one list for the module.
- **Names, not IDs.** Categories and applications are named in config and resolved at plan time against the account's own Cloudflare catalogue (`cloudflare_zero_trust_gateway_categories_list`, and `cloudflare_zero_trust_gateway_app_types_list` with `max_items = 10000` to avoid silent truncation). A name that does not resolve fails the plan. DLP profiles are the exception: they are referenced by UUID because no data source resolves them by name.
- **Compiled expressions.** Account trees never write wirefilter. The module compiles `match` selectors into:
  - `(destination terms OR'd) and (each constraint AND'd)`
  - Destination terms: `domains`, `hosts`, `sni_domains`, `sni_hosts`, `applications`, `content_categories`, `security_categories`, `destination_ip_cidrs`
  - Constraints: `source_ip_cidrs`, `destination_ports`, `protocols`, `http_methods`, `dlp_profile_ids`
  - `upload_file_types` and `download_file_types` are OR'd with each other, then AND'd with the rest
  - `negate` inverts the whole traffic expression
  - `identity` terms (`user_emails`, `user_group_names`, `user_group_emails`, `user_group_ids`) are OR'd
  - Raw `traffic_expression`, `identity_expression` and `device_posture_expression` are escape hatches. They replace the compiled expression for that dimension; setting both is refused.
- **Precedence.** Gateway walks each builder in ascending precedence and stops at the first allow or block that matches. Precedence must be **unique across the whole account, all builders together** (module precondition; Cloudflare returns 409 otherwise). Precedence below `reserved_precedence_ceiling` (100) belongs to the baseline and is refused for account policies.
- **Policy identity.** The module keys policies by lowercased `name`. Renaming a policy destroys and recreates it.
- **Account settings are a singleton.** `gateway_settings` (TLS decryption, inspection mode, antivirus, sandbox, block page, etc.) defaults to `null`, which leaves the Zero Trust dashboard authoritative.
- **Inspection CA.** `gateway_inspection_certificate` optionally generates and activates the root CA Gateway presents (default validity 1,826 days, `create_before_destroy`). Distributing that root to devices is out of scope for Terraform.

## A2. Global parameters (effective platform defaults)

| Variable | Effective default | Purpose |
|---|---|---|
| `gateway_baseline_policies` | `[]` (set per account) | Which catalogue entries the account opts into |
| `gateway_security_categories` | `"Command and Control & Botnet"`, `"Malware"` | Feeds both security-threat baselines. The variable default is `[]`; `defaults.auto.tfvars` sets these two |
| `gateway_blocked_content_categories` | `[]` | Acceptable-use decision, so no platform default |
| `gateway_bypass_applications` | `[]` | Applications exempt from TLS inspection. Account-level decision |
| `gateway_dlp_profile_ids` | `[]` | DLP profile UUIDs from the Zero Trust dashboard |
| `gateway_quarantine_file_types` | `[]` | Must be one of: exe, pdf, doc, docm, docx, rtf, ppt, pptx, xls, xlsm, xlsx, zip, rar |
| `reserved_precedence_ceiling` | `100` | Precedence below this is baseline-only |
| `restricted_actions` | `[]` | Gateway actions refused for account and baseline policies. See issue 6 |
| `default_block_notification` | `enabled = true`, msg "This request was blocked by your organisation's internet policy." | WARP client notification for every block policy that sets none of its own (baseline and account). Variable default is `null`; no `support_url` is set |
| `default_untrusted_cert_action` | `error` | Applied to every account HTTP **allow** policy that sets nothing, so dashboard edits show as drift |
| `allow_dlp_payload_logging` | `false` | Guard: storing matched DLP content in logs |
| `allow_disabling_dnssec_validation` | `false` | Guard: per-policy DNSSEC opt-out |
| `allow_untrusted_certificate_pass_through` | `false` | Guard: silently serving sites with invalid certificates |
| `allow_uninspected_http_policies` | `false` | Guard: HTTP policies while TLS decryption is off or unmanaged |
| `allow_antivirus_fail_closed` | `false` | Guard: blocking every file that could not be scanned |
| `gateway_settings` | `null` (unmanaged) | Account-level Gateway configuration |
| `gateway_inspection_certificate` | `null` (unmanaged) | Generate and activate the inspection CA |

## A3. Baseline catalogue

All entries are enabled, apply to every user and device (no identity, posture, schedule or expiry scope), and have the default block notification attached when the action is `block`.

| Key | Dashboard name | Builder | Action | Precedence | Compiled match | Requires |
|---|---|---|---|---|---|---|
| `block_security_threats` | Baseline - block security threats (DNS) | dns | block | 10 | `any(dns.security_category[*] in {…})` | `gateway_security_categories`. Block page on |
| `bypass_trusted_applications` | Baseline - do not inspect trusted applications | http | off (Do Not Inspect) | 20 | `any(app.ids[*] in {…})` | `gateway_bypass_applications` |
| `block_security_threats_http` | Baseline - block security threats (HTTP) | http | block | 30 | `any(http.request.uri.security_category[*] in {…})` | `gateway_security_categories` |
| `block_disallowed_content` | Baseline - block disallowed content categories | dns | block | 40 | `any(dns.content_category[*] in {…})` | `gateway_blocked_content_categories`. Block page on |
| `block_dlp_matches` | Baseline - block DLP matches | http | block | 50 | `any(dlp.profiles[*] in {…})` | `gateway_dlp_profile_ids` |
| `quarantine_risky_downloads` | Baseline - quarantine risky downloads | http | quarantine | 60 | `any(http.download.file.types[*] in {…})` | `gateway_quarantine_file_types` (also sent as the quarantine file-type setting) |

**Block reasons shown to users:**

- Security threats (DNS and HTTP): "This site is categorised as a security threat."
- Disallowed content: "This site is in a category the organisation does not permit."
- DLP: "This request contained data the organisation does not permit to be sent to this destination."

**Evaluation order by builder:**

- **DNS:** 10 security threats → 40 disallowed content → account DNS policies (100+)
- **HTTP:** 20 Do Not Inspect → 30 security threats → 50 DLP → 60 quarantine → account HTTP policies (100+)
- **Network:** no baseline entries. Account network policies only (100+)

**Why the security categories appear twice:** a DNS policy only sees queries sent to Gateway's resolver. A browser or malware using DNS-over-HTTPS to a third-party resolver never asks it. The HTTP policy sees the connection either way, provided TLS decryption is on.

## A4. Plan-time guardrails (preconditions)

**Layer (`preflight.tf`).** The plan fails when:

- a category name does not resolve against the account catalogue (the error lists every valid name);
- an application name does not resolve (the error gives the catalogue size and up to 40 near matches);
- a selected baseline's parameter list is empty (an empty set renders as `in {}`, which Cloudflare rejects);
- an account policy uses a precedence below `reserved_precedence_ceiling`;
- an account or baseline policy uses an action in `restricted_actions`;
- an account policy enables DLP payload logging without `allow_dlp_payload_logging`;
- an account policy disables DNSSEC validation without `allow_disabling_dnssec_validation`;
- account HTTP policies (other than `off`) exist while TLS decryption is off or `gateway_settings` is unmanaged, without `allow_uninspected_http_policies` (see issue 4);
- a policy or `default_untrusted_cert_action` uses `pass_through` without `allow_untrusted_certificate_pass_through`.

**Module, on every policy.** The plan fails when:

- an action does not exist for the builder (DNS: allow, block, override, safesearch, ytrestricted; network: allow, block, l4_override; HTTP: allow, block, off, on, scan, noscan, isolate, noisolate, quarantine, redirect);
- a selector does not exist for the builder (for example ports on DNS, `domains` on network, DLP outside HTTP);
- two policies share a precedence, in any builder;
- a policy has no selector at all and `match_all_traffic` is not set;
- `match_all_traffic` is combined with allow, off, noscan or noisolate;
- a Do Not Inspect policy matches on something only visible after decryption (DLP, methods, file types);
- a DLP match is combined with off or noscan;
- a structured matcher and a raw expression are set for the same dimension;
- an action is missing its setting (redirect target, quarantine file types, L4 override, DNS override);
- a setting is given to a builder that ignores it.

**Module, on account settings (only when `gateway_settings` is set).** The plan fails when:

- HTTP policies (other than `off`) exist while `tls_decrypt.enabled` is false, unless `allow_uninspected_http_policies`;
- `body_scanning` is set while TLS decryption is off;
- `antivirus.fail_closed = true` without `allow_antivirus_fail_closed`;
- the module is asked to generate a CA while `settings.certificate.id` names another one.

**Input validation also checks:**

- policy keys match `^[a-z0-9_]+$` and policy names are unique;
- `type` is dns, network or http;
- baseline names exist in the catalogue and are not repeated;
- DLP profile IDs are UUIDs;
- quarantine file types are in the sandbox list;
- `restricted_actions` entries are real Gateway actions;
- `default_untrusted_cert_action` is pass_through, block or error.

## A5. Tenant extension points

- **`gateway_policies`**: dns, network and http policies at precedence 100 and above, with `match`, `identity`, `device_posture_check_ids`, raw expressions, `schedule`, `expiration` and `settings`.
- **Baseline parameters**: the five lists in A2.
- **`gateway_settings`**: TLS decryption, inspection mode, protocol detection, body scanning, antivirus, sandbox, block page, activity log, browser isolation, extended email matching, FIPS, max TTL.
- **`gateway_inspection_certificate`**.

`identity.user_group_names` uses the names the IdP sends. For Entra ID that needs `support_groups = true` on the provider in the zerotrust layer.

## A6. Sample account deployments

### account_a

**Baseline selected:** `block_security_threats`, `block_security_threats_http`, `block_dlp_matches`, `quarantine_risky_downloads`.

- **Security categories (overrides platform default):** Command and Control & Botnet, Malware, Phishing, Cryptomining, Spyware, Spam, DGA Domains, DNS Tunneling, Anonymizer.
- **DLP profiles:** one placeholder UUID (`33333333-…`). EDIT required.
- **Quarantine file types:** exe, zip, rar.
- **Not selected:** `block_disallowed_content` (no content categories set) and `bypass_trusted_applications` (the bypass is done by an account policy at HTTP 110 instead).
- **`gateway_settings`:** not set, so TLS decryption is unmanaged (see issue 2).

**DNS policies**

| Key | Name | Action | Prec. | Match |
|---|---|---|---|---|
| `block_public_dns_resolvers` | Block third-party DNS resolvers | block | 100 | domains: dns.google, cloudflare-dns.com, one.one.one.one, dns.quad9.net, doh.opendns.com, dns.nextdns.io, dns.adguard-dns.com, doh.cleanbrowsing.org, doh.dns.sb, dns.alidns.com |
| `block_newly_registered_domains` | Block newly registered domains | block | 110 | content: New Domains, Newly Seen Domains |
| `block_peer_to_peer` | Block peer-to-peer file sharing | block | 120 | content: Peer-to-Peer |
| `block_known_bad_domains` | Block known bad domains | block | 130 | domains: a-really-bad-website.net (placeholder) |

**Network policies.** Each allow sits immediately above the block it exempts.

| Key | Name | Action | Prec. | Match |
|---|---|---|---|---|
| `allow_sanctioned_smtp_relay` | Allow the sanctioned SMTP relay | allow | 100 | 203.0.113.25/32, tcp/587. EDIT |
| `block_direct_smtp` | Block direct outbound SMTP | block | 110 | tcp 25, 465, 587 |
| `allow_sanctioned_admin_endpoints` | Allow sanctioned administrative endpoints | allow | 120 | 198.51.100.0/24, tcp 22, 3389. EDIT |
| `block_insecure_admin_ports` | Block outbound administrative ports | block | 130 | tcp 22, 23, 445, 3389 |
| `block_encrypted_dns_transports` | Block DNS-over-TLS and DNS-over-QUIC | block | 140 | tcp/udp 853 |
| `block_third_party_resolver_addresses` | Block third-party resolvers by address | block | 150 | 8.8.8.8, 8.8.4.4, 1.1.1.1, 1.0.0.1, 9.9.9.9, 149.112.112.112, 208.67.222.222, 208.67.220.220, 94.140.14.14, 94.140.15.15 on tcp/udp 53 and 443 |
| `block_p2p_and_tor_ports` | Block peer-to-peer and Tor ports | block | 160 | tcp/udp 6881–6889, 9001, 9030, 9050, 9051 |

**HTTP policies**

| Key | Name | Action | Prec. | Match | Notes |
|---|---|---|---|---|---|
| `inspect_saas_authentication_endpoints` | Inspect SaaS authentication endpoints | on (inspect) | 100 | hosts: login.microsoftonline.com, login.microsoft.com, login.windows.net, accounts.google.com | Keeps sign-in decrypted so tenant headers can be added |
| `bypass_trusted_applications` | Do not inspect trusted applications | off | 110 | application: Microsoft 365 | |
| `restrict_microsoft_365_tenants` | Restrict Microsoft 365 to corporate tenants | allow | 120 | the three Microsoft login hosts | **Disabled.** Intended to inject `Restrict-Access-To-Tenants` / `Restrict-Access-Context`. See issue 3 |
| `restrict_google_workspace_tenants` | Restrict Google Workspace to corporate domains | allow | 130 | domain: google.com | **Disabled.** Intended to inject `X-GoogApps-Allowed-Domains`. See issue 3 |
| `allow_sanctioned_software_sources` | Allow downloads from sanctioned software sources | allow | 200 | domain: example.org | EDIT. Exempts these domains from every HTTP policy below it |
| `block_high_risk_downloads` | Block high-risk file downloads | block | 210 | download: exe, msi, iso, ps1, vbs, bat | |
| `block_uploads_to_generative_ai` | Block uploads to unsanctioned generative AI | block | 220 | application "Generative AI" AND upload: pdf, doc, docx, xls, xlsx, ppt, pptx, txt, csv, zip | |
| `block_uploads_to_unmanaged_storage` | Block uploads to unmanaged storage | block | 230 | domain example.org AND upload: pdf, docx, xlsx | Placeholder domain |
| `isolate_low_reputation_sites` | Isolate low-reputation sites | isolate | 300 | content: New Domains, Newly Seen Domains, Parked & For Sale Domains | Needs Browser Isolation on the plan |
| `isolate_contractor_browsing` | Isolate contractor browsing | isolate | 310 | identity: user group "Contractors" | Identity-only, no traffic selector |
| `block_streaming_during_work_hours` | Block streaming during work hours | block | 400 | domain: example.com | **Disabled.** Schedule Europe/London, Mon–Fri 09:00–12:30 and 13:30–17:30 |

Every HTTP allow above gets `untrusted_cert_action = error` from the platform default.

### account_b

- **Baseline selected:** `block_security_threats`, `block_security_threats_http`, using the platform default categories (Command and Control & Botnet, Malware).
- **Account policy:** `block_traffic_from_unknown_ranges` ("Block traffic from unknown source ranges"), network, block, precedence 100. Match is `negate = true` on source 198.51.100.0/24 and 192.0.2.0/24, so anything from outside those ranges is blocked.
- **Not used:** content categories, bypass, DLP, quarantine.
- **`gateway_settings`:** not set (see issue 4).

# Part B: Access

## B1. Design model

- **One Zero Trust organisation per account.** Terraform adopts and manages it but cannot create it (the provider uses PUT). The team name is chosen once, out of band. The layer reads the existing organisation at plan time; on an account without one, that read fails the plan. If `zero_trust_team_name` is unset, the existing team name is adopted.
- **Objects:**
  - **Identity providers** (login methods). OAuth client secrets come only from the pipeline (`TF_VAR_identity_provider_secrets`), keyed by the same key.
  - **Service tokens.** The generated secret is held in state and is not a module output.
  - **Access groups**: reusable audiences.
  - **Access policies**: reusable, account-level. A decision plus `include` / `exclude` / `require` rule sets.
  - **Access applications**: attach policies by key, in evaluation order.
- **Rule sets.** Each value in a rule set becomes its own Cloudflare rule. Cloudflare then applies `include` as any-of, `require` as all-of and `exclude` as none-of (see issue 7).
- **Policy order is evaluation order.** The first matching policy decides, so deny policies go first. The layer preserves list order.
- **Identity is the name.** The module keys every object by lowercased `name`, so renaming one destroys and recreates it. Keys are handles only.
- **Application destinations.** `domain` is always prepended to `destinations`, so an application cannot omit its own hostname. `extra_destinations` can be public (hostname/URI, wildcards allowed) or private (hostname, CIDR, protocol, port range, virtual network).
- **Resource tags** for applications are applied after apply by `.github/scripts/resource-tags.sh`, not by the provider.
- **Apply tier 3**, after the tier that creates zones.

## B2. Platform defaults (organisation-level baseline)

Variable defaults and `defaults.auto.tfvars` agree for every entry below.

| Variable | Effective default | Effect |
|---|---|---|
| `default_session_duration` | `24h` | Organisation session length. Policies and applications can override it |
| `default_warp_auth_session_duration` | `24h` | WARP authentication session |
| `user_seat_expiration_inactive_time` | `730h` | Cloudflare's minimum. Frees seats held by inactive users |
| `default_service_token_duration` | `8760h` (1 year) | Applied to tokens that set no duration. `forever` is accepted |
| `restricted_policy_decisions` | `["bypass"]` | Decisions refused at plan time |
| `allowed_email_domains` | `[]` (any domain) | When set, `include` rules may only admit these domains |
| `lock_dashboard_to_read_only` | `false` | Turn on once the account is steady, so this repo is the only route to an Access change |
| `auto_redirect_to_identity` | `false` | Skip the IdP chooser |
| `allow_authenticate_via_warp` | `false` | WARP device identity instead of a browser login |
| `allow_team_name_change` | `false` | Guard against renaming the team domain |
| `login_design` | `null` | Login page branding |

## B3. Policy decisions

| Decision | Meaning | Baseline status |
|---|---|---|
| `allow` | Authenticate, then evaluate the rules | Permitted |
| `deny` | Refuse | Permitted |
| `non_identity` | Match on posture, IP or service token with no login (machine callers) | Permitted |
| `bypass` | No authentication at all | **Refused** by `restricted_policy_decisions` |

## B4. Plan-time guardrails (preconditions)

**Layer (`preflight.tf`).** The plan fails when:

- the account has no team name and none is configured;
- the configured team name differs from the existing one, without `allow_team_name_change` (a rename changes every Access URL and forces WARP re-enrolment);
- a `group_keys`, `service_token_keys`, identity provider key or `policy_keys` reference matches nothing;
- an IdP-bound condition sets both `identity_provider_key` and `identity_provider_id`, or neither;
- a policy uses a restricted decision (`bypass` by default);
- an `include` rule admits an email or domain outside `allowed_email_domains` (only when that list is non-empty);
- an OAuth-type identity provider has no secret in `identity_provider_secrets`;
- a secret exists for an identity provider that does not;
- `resource_tags` for applications are invalid.

**Module.** The plan fails when:

- an `include`, `exclude` or `require` set names no conditions;
- every policy attached to an application is a deny (nobody could reach it);
- a group, service token, IdP or policy name does not resolve (defence in depth behind the layer checks).

**Input validation also checks:**

- keys match `^[a-z0-9_]+$` and names are unique, for identity providers, service tokens, groups, policies and applications;
- `decision` is allow, deny, bypass or non_identity;
- every application attaches at least one policy;
- access groups do not use `group_keys` (it would be a dependency cycle);
- the team name, Go durations and email domains are well-formed.

## B5. Tenant extension points

- **`identity_providers`**, plus `identity_provider_secrets` from the pipeline
- **`service_tokens`**
- **`access_groups`**
- **`access_policies`**: also supports approval groups, purpose justification, isolation and per-policy session length
- **`access_applications`**: all application types the provider supports, plus cookie settings, CORS, `service_auth_401_redirect`, custom deny pages, launcher visibility and IdP restriction

## B6. Sample account deployments

### account_a

- **Organisation:** team `account-a`, name "Account A Internal Applications". All other organisation settings take the platform defaults (24h sessions, dashboard not locked, no email domain restriction).
- **Identity provider:** "Entra ID" (`azureAD`) with `support_groups = true`, `conditional_access_enabled = true`, and SCIM with user and seat deprovisioning.
- **Service token:** "CI Pipeline", 1-year default lifetime.
- **Groups:**
  - "Platform Engineers": Entra group object ID `22222222-…` (placeholder).
  - "Staff": email domain example.com. Not referenced by any policy.

**Policies**

| Key | Name | Decision | Include | Require | Session |
|---|---|---|---|---|---|
| `block_untrusted_countries` | Block Untrusted Countries | deny | country KP | | |
| `platform_engineers_mfa` | Platform Engineers with MFA | allow | group Platform Engineers | auth method `mfa` AND login method Entra ID | 8h |
| `ci_service_token` | CI Pipeline Service Token | non_identity | service token CI Pipeline | | |

`auth_methods = ["mfa"]` means the IdP asserted MFA. Cloudflare does not prompt for a second factor itself.

**Applications**

| Key | Name | Destinations | Policies, in order | Settings |
|---|---|---|---|---|
| `grafana` | Grafana | grafana.example.com, metrics.example.com | block_untrusted_countries → platform_engineers_mfa → ci_service_token | 8h session, in launcher, `service_auth_401_redirect` |
| `pages_admin_portal` | Pages - account-a-admin | admin.example.com, account-a-admin.pages.dev, *.account-a-admin.pages.dev | block_untrusted_countries → platform_engineers_mfa | 8h session, in launcher |
| `pages_docs_site` | Pages previews - account-a-docs | *.account-a-docs.pages.dev (previews only; production is public) | block_untrusted_countries → platform_engineers_mfa | Defaults |

The bare `account-a-admin.pages.dev` hostname is listed on purpose: protecting only the custom domain would leave production reachable on pages.dev without a login, and a `*.` wildcard does not match the bare name.

### account_b

- **Organisation:** team name not set, so the existing one is adopted. Platform defaults otherwise.
- **Identity provider:** "Entra ID" (`azureAD`), `support_groups = true`, no SCIM.
- **Group:** "Staff", email domain example.net.
- **Policy:** "Staff Only", allow, include group Staff.
- **Application:** "Internal Wiki" on wiki.example.net, policy Staff Only, in launcher.
- **Not used:** deny policies, MFA requirement, service tokens.

# Part C: Related controls outside these layers

- **Device posture (`deployment/layers/device_posture/`):** platform defaults are a 5 min client schedule, 10 min integration polling, an expiration derived at twice the polling period, signed-binary checks required, and the legacy `tanium` type refused.
  - account_a rules: Cloudflare One Client running, disk encryption (Windows, macOS), OS version (Windows 11 23H2+, macOS 14.4+), firewall (Windows), CrowdStrike Falcon sensor (Windows).
  - account_b rules: Cloudflare One Client running, disk encryption (Windows, macOS, Linux).
  - **No sample Gateway or Access rule references a posture check** (`device_posture_check_ids` / `device_posture_ids` are unused). Posture is collected but not enforced.
- **Pages layer:** emits `pages_access_applications`, which is copied by hand into the zerotrust account tree. The pages token has no Zero Trust scope, so the zerotrust entry is the only protection on those sites.
- **Tunnels layer:** manages cloudflared tunnels, routes and virtual networks, which private Access destinations and Gateway network rules can target.
- **Not managed anywhere in the repo** (no resource exists in any module): Gateway egress and resolver policies, DNS locations / proxy endpoints, Zero Trust lists, DLP profiles, WARP device settings profiles and split tunnels, Access custom pages, Access mTLS certificates, CASB. The HLD should list these as dashboard-managed, out of scope or future work.

# Known issues / open items

Flag these in the HLD; do not treat them as design intent.

1. **account_a `gateway.tfvars` cannot plan: precedence collides across builders.** DNS uses 100–130, network 100–160 and HTTP 100–130, so 100, 110, 120 and 130 are each used three times. The module requires precedence to be unique across the whole account. The file's header comment ("each have their own precedence sequence") and the layer's `gateway_policies` description ("Evaluation order within this policy's type") describe per-builder numbering, which contradicts the module and the baseline catalogue comment.
2. **account_a Gateway also fails the uninspected-HTTP guard.** It defines HTTP policies but leaves `gateway_settings` unset, so TLS decryption is "unmanaged" and `allow_uninspected_http_policies` is false.
3. **Tenant restriction headers are never sent.** `restrict_microsoft_365_tenants` and `restrict_google_workspace_tenants` set `settings.add_headers`, but neither the layer variable nor the module has that attribute, and Terraform drops undeclared object attributes without error. Enabling either rule would create a plain HTTP allow with no headers. For Google, that is an allow on google.com that exempts all Google traffic from every HTTP policy below it (including the download and upload blocks) and restricts nothing. Both ship `enabled = false`.
4. **Baseline HTTP policies are not covered by the uninspected-HTTP guard when `gateway_settings` is null.** The layer check only scans account `gateway_policies`, and the module check only exists when the settings resource does. account_b plans cleanly with `block_security_threats_http` while inspection is unmanaged; unless TLS decryption is already on in the dashboard, that rule only sees plaintext HTTP.
5. **The Gateway layer has no `imports.tf`.** `gateway.tf`, `variables.tf` and the module's `settings.tf` all say the account configuration singleton is adopted by an import block in the layer. None exists, so the first apply that sets `gateway_settings` writes the object from config alone, and dashboard-only values are at risk of being dropped.
6. **`restricted_actions = ["off"]` also blocks the baseline bypass.** The `defaults.auto.tfvars` comment says it stops inspection being turned off "outside the baseline", but the precondition checks selected baseline policies too, so `bypass_trusted_applications` would be refused.
7. **Access `require` semantics are misdescribed.** The layer's `access_policies` description says "A rule set is an OR across everything named in it". Each value becomes a separate Cloudflare rule, and Cloudflare ANDs `require` rules. That is what account_a relies on (MFA AND Entra ID). But two values in one `require` field (for example two country codes) would demand both, which can never match.
8. **Gateway policy identity is the name, not the key.** The `gateway_policies` description says renaming the key destroys and recreates the policy. The module keys by name, so a key rename is a no-op and a name rename is a recreate. (The Access layer describes this correctly.)
9. **Stale comment in account_a `gateway.tfvars`.** `allow_sanctioned_software_sources` says the baseline quarantine rule is at HTTP precedence 40. It is at 60; 40 is the DNS content baseline.
10. **Placeholders that make account_a rules inert or harmful until edited:**
    - the DLP profile UUID (`block_dlp_matches` matches nothing);
    - the SMTP relay address;
    - the bastion range 198.51.100.0/24, which means precedence 130 blocks **all** outbound SSH, Telnet, SMB and RDP;
    - example.org for software sources and unmanaged storage;
    - `a-really-bad-website.net`, example.com for streaming;
    - the Microsoft and Google tenant values.
11. **`GETTING_STARTED.md` does not exist.** It is referenced from `deployment/layers/zerotrust/organization_lookup.tf` and `deployment/accounts/account_a/zerotrust.tfvars` as the place to find team-name bootstrap steps.
12. **Access sample gaps worth a design decision:** `allowed_email_domains` is empty and the dashboard is unlocked on both accounts; account_b has no deny policy and no MFA requirement; account_a's "Staff" group is unused; and no posture check is enforced anywhere (see Part C).
