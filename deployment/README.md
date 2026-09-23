# `deployment` - the deployment template

Everything you edit lives here. The modules under [../modules/](../modules/) stay agnostic: flat arguments, real IDs, one resource group each, no knowledge of accounts, keys or profiles. You should avoid editing ".tf" files directly within target environments, as this repository follows an upstream and downstream architectural pattern. You maintain your canonical template repository, which is then copied or forked to target customer repositories where edits are restricted to `.tfvars` files. Any modifications to `.tf` orchestrators or underlying modules should take place in the upstream repository first, before being propagated downstream.

## Directory Structure

```deployment/
├── layers/                            # code, shared by every account
│   ├── account_governance/            # own state: members, user groups, RBAC
│   ├── bulk_redirects/                # own state: URL redirect lists and execution ruleset
│   ├── device_posture/                # own state: device posture checks, MDM and EDR integrations
│   ├── dns/                           # own state: per-zone DNS records
│   ├── gateway/                       # own state: SWG egress filtering, TLS inspection, root CA
│   ├── lists/                         # own state: account-level IP, ASN and hostname lists
│   ├── load_balancing/                # own state: monitors, pools, zone load balancers
│   ├── logpush/                       # own state: Logpush jobs, account and zone log streams
│   ├── origin_pulls/                  # own state: Authenticated Origin Pulls, client certificates, per-hostname edge-to-origin mTLS
│   ├── pages/                         # own state: Pages projects, branch deployment rules, bindings, custom domains
│   ├── r2/                            # own state: buckets, CORS, lifecycle, retention, domains
│   ├── rules/                         # own state: cache rules, transform rules, origin rules
│   ├── tunnels/                       # own state: Cloudflare Tunnels, public hostnames, private network routes
│   ├── turnstile/                     # own state: Turnstile widgets, the sitekey and secret a form is protected by
│   ├── waf/                           # own state: firewall custom rules, rate limiting
│   ├── wan/                           # own state: Magic WAN IPsec and GRE tunnels, static routes
│   ├── workers/                       # own state: Worker scripts, KV namespaces, D1 databases, queues, routes, crons
│   ├── zerotrust/                     # own state: Access applications, policies, service tokens, IdPs
│   └── zones/                         # own state: zones, TLS posture, settings, bot management
└── accounts/                          # config, one tree per Cloudflare account
    ├── account_a/
    │   ├── account.tfvars             # account id       -> every layer
    │   ├── account_governance.tfvars  # dashboard access -> account_governance
    │   ├── bulk_redirects.tfvars      # URL redirects    -> bulk_redirects
    │   ├── device_posture.tfvars      # posture checks   -> device_posture
    │   ├── dns.tfvars                 # DNS records      -> dns
    │   ├── gateway.tfvars             # egress filtering -> gateway
    │   ├── lists.tfvars               # shared lists     -> lists
    │   ├── load_balancing.tfvars      # load balancers   -> load_balancing
    │   ├── logpush.tfvars             # log streams      -> logpush
    │   ├── origin_pulls.tfvars        # origin mTLS      -> origin_pulls
    │   ├── pages.tfvars               # Jamstack sites   -> pages
    │   ├── r2.tfvars                  # object storage   -> r2
    │   ├── rules.tfvars               # traffic rules    -> rules
    │   ├── tags.tfvars                # resource tags    -> zones, zerotrust, r2, workers
    │   ├── tunnels.tfvars             # Cloudflare Tunnel -> tunnels
    │   ├── turnstile.tfvars           # Turnstile widgets -> turnstile
    │   ├── waf.tfvars                 # firewall rules   -> waf
    │   ├── wan.tfvars                 # site tunnels     -> wan
    │   ├── workers.tfvars             # edge compute, KV, D1, queues -> workers
    │   ├── zerotrust.tfvars           # Access posture   -> zerotrust
    │   ├── zone_config.tfvars         # zone settings    -> zones
    │   └── zones.tfvars               # zone inventory   -> zones, bulk_redirects, dns, waf, lb, logpush, origin_pulls, pages, r2, rules, tunnels, workers
    └── account_b/
        └── ...
```

Each layer is a root module with its own state file, holding `terraform.tf`, `providers.tf`, `variables.tf`, `locals*.tf`, one `<subject>.tf`, `preflight.tf`, `outputs.tf` and its own `defaults.auto.tfvars` where platform baselines apply.

Layers are named after the Cloudflare product they manage, with no artificial numeric prefixes in directory names. Instead, execution ordering is determined by real infrastructure dependencies and enforced through a sequential multi-tier pipeline model.

## Sequential Dependency Model (3-Tier Pipeline)

Infrastructure execution follows three deterministic tiers. Everything within a single tier runs concurrently, whilst each tier is planned and applied strictly after the preceding tier completes:

```
Tier 1: Platform Authorisation
└── account_governance                 (applied first and alone; establishes RBAC and scoped permissions)

Tier 2: Foundational Zones & Account Services
├── zones                              (provisions zone containers, rate plans, and baseline TLS posture)
├── bulk_redirects                     (account-scoped redirect lists and rules; independent of zones)
├── device_posture                     (account-scoped posture checks and MDM/EDR integrations; required before zerotrust)
├── gateway                            (account-scoped SWG policies, TLS decryption settings, root CA)
├── lists                              (account-scoped IP, ASN, and hostname lists; required before WAF)
├── turnstile                          (account-scoped widgets; attached to no zone, so nothing waits on it)
└── wan                                (account-scoped Magic WAN tunnels and static routes)

Tier 3: Zone-Dependent & Consumer Layers
├── dns                                (resolves zone IDs via data source; creates DNS records)
├── load_balancing                     (resolves zone IDs; provisions origin pools and health monitors)
├── logpush                            (resolves zone IDs for zone-scoped jobs; pushes logs to a SIEM or storage)
├── origin_pulls                       (resolves zone IDs; enables Authenticated Origin Pulls and uploads client certificates)
├── pages                              (resolves zone IDs; writes the proxied CNAME behind each custom domain)
├── r2                                 (provisions buckets; binds custom domains to existing zones)
├── rules                              (resolves zone IDs; manages cache, transform, and origin rules)
├── tunnels                            (resolves zone IDs; publishes tunnel hostnames as proxied CNAMEs)
├── waf                                (resolves zone IDs; consumes account lists created in Tier 2)
├── workers                            (resolves zone IDs; binds script routes and custom domains; provisions KV, D1 and queues)
└── zerotrust                          (Access hostnames require valid, proxied DNS records)
```

Tier membership is derived directly from the Terraform source code - calling the `zone_base` module means Tier 2, resolving a zone with `data "cloudflare_zone"` means Tier 3 - except where the source cannot express the dependency at all. Those two layers declare their own tier in a `tier.tf` holding `locals { apply_tier = <n> }`, which `tf-matrix.sh` reads in preference to the derivation:
- **Tier 1 (`account_governance`):** Account-wide permissions and resource-group scopes. Every downstream token is evaluated against what this layer applies, so it runs on its own first. Declared in `tier.tf`, because the dependency is on Cloudflare's authorisation decision rather than on any Terraform attribute.
- **Tier 2 (`zones`, `bulk_redirects`, `device_posture`, `gateway`, `lists`, `turnstile`, `wan`):** `zones` creates the zone containers at Cloudflare. The remaining layers touch no zones, so nothing waits on them. `lists` is deliberately placed in Tier 2 so that named lists exist before `waf` references them, and `device_posture` so that a posture rule exists before a `zerotrust` Access policy requires it.
- **Tier 3 (`dns`, `load_balancing`, `logpush`, `origin_pulls`, `pages`, `r2`, `rules`, `tunnels`, `waf`, `workers`, `zerotrust`):** These layers resolve zones dynamically via `data "cloudflare_zone"`, which fails at plan time until Tier 2 has created the zone. `tunnels` resolves one for the proxied CNAME behind each public hostname, `pages` one for the CNAME behind each custom domain, and `logpush` one for each zone-scoped job. `origin_pulls` resolves one per zone it configures, and belongs behind `zones` for a second reason: the zone's SSL mode has to be `full` or `strict` before authenticating to the origin means anything. `zerotrust` is included here by declaration in its own `tier.tf`, because Access applications are addressed by hostname and require the corresponding zone and DNS record to exist, yet the layer never reads a zone for the derivation to find.

## Why split this way

**Account isolation over single-state monoliths.** One `provider "cloudflare"` block carries one API token, and Terraform cannot pass a dynamic provider alias into a `for_each` module block. Accounts cannot be `for_each` keys: each account requires its own run, with its own scoped token and isolated state key. This model guarantees blast-radius containment: a token compromised for one customer cannot reach another.

**Product isolation over combined states.** A WAF, DNS, or load balancer apply cannot propose destroying a zone, because zones are not in its state. Zone deletion is the most destructive failure mode in Cloudflare, as it immediately cascades to eliminate all DNS records. Splitting state also allows each layer's pipeline runner to hold a tightly scoped token: `waf` requires `Zone WAF:Edit` and `Zone:Read`, never `Zone:Edit`. The boundary is strictly enforced across roles: `account_governance` is the only layer whose credentials can grant administrative access, and `zerotrust` is the only layer that controls access behind Cloudflare Access. Neither holds zone-level modification rights.

**Zone as a `for_each` key, not a directory.** Maintaining a directory per account and zone would mean onboarding a zone requires adding duplicated `.tf` orchestrator files. A fleet-wide module version bump would touch hundreds of files. Adding a zone here requires editing only `zones.tfvars`, `zone_config.tfvars`, and `dns.tfvars`.

**DNS separated from Zone lifecycle.** Zone lifecycle management (creation, rate plan subscription, TLS minimum versions, and security level) is separated from high-velocity DNS record management. Routine record changes cannot trigger zone-level recreation or setting drift, and teams managing DNS records do not require permissions to alter zone subscriptions or TLS settings.

## Layers do not read each other's state

The `dns`, `waf`, `load_balancing`, `logpush`, `origin_pulls`, `pages`, `r2`, `rules`, `tunnels`, and `workers` layers resolve a zone key to a zone ID using `data "cloudflare_zone"` filtered by name and account ID, rather than reading `terraform_remote_state`. State files remain completely decoupled: any layer can be applied, re-initialised, or migrated without affecting the others.

This design requires the Cloudflare API to be accessible at plan time for consumer layers, and plans will fail if the zone does not yet exist. Apply `zones` first; `dns`, `waf`, `load_balancing`, `logpush`, `origin_pulls`, `pages`, `r2`, `rules`, `tunnels`, and `workers` can then plan and apply concurrently.

`account_governance` queries the API to resolve role, permission group, and resource group names to IDs. `zerotrust` queries the account's existing Zero Trust organisation to adopt the configured team name. `gateway` dynamically resolves Cloudflare's content categories, security categories, and application catalogues so that configuration files reference human-readable names like `"Microsoft 365"` rather than arbitrary IDs like `606`.

`wan`, `bulk_redirects`, `lists`, `turnstile`, and `device_posture` are completely account-scoped and contain no zone data sources.

## Config precedence

1. `layers/<layer>/defaults.auto.tfvars`: platform baseline, auto-loaded from the layer's working directory. Customer-agnostic.
2. `accounts/<account>/*.tfvars`: passed explicitly with `-var-file` flags, overriding defaults.
3. `local.auto.tfvars` in a layer directory: operator local experiments. Strictly Gitignored.

Terraform `-var-file` arguments do not merge maps across files: if two files define the same variable, the last file wins wholesale. Account configuration is therefore partitioned by variable rather than by zone: `zones.tfvars` owns the zone inventory, `zone_config.tfvars` owns zone settings, `dns.tfvars` owns DNS records, and `waf.tfvars` owns firewall rules. No two files define the same top-level variable.

The helper script `.github/scripts/tf-varfiles.sh` verifies variable declarations dynamically, ensuring that only the relevant `.tfvars` files are passed to each layer.

## What is committed

Layer defaults are customer-agnostic. Account configuration files contain account IDs, domain names, IP address ranges, and routing topologies. This is operational configuration, not secret material, and this repository is protected by private repository access controls and RBAC.

The following secrets must never be committed to source control:

```bash
export CLOUDFLARE_API_TOKEN="<per-account, per-layer scoped token>"
export AWS_ACCESS_KEY_ID="<R2 access key for state backend>"
export AWS_SECRET_ACCESS_KEY="<R2 secret key for state backend>"
export TF_VAR_identity_provider_secrets='{"entra_id":"<oauth_client_secret>"}'
export TF_VAR_wan_ipsec_tunnel_psks='{"london_primary":"<pre_shared_key>"}'
export TF_VAR_logpush_destination_secrets='{"audit_archive":"r2://<bucket>/audit/{DATE}?account-id=<id>&access-key-id=<key_id>&secret-access-key=<secret>"}'
export TF_VAR_device_posture_integration_secrets='{"intune":{"client_secret":"<entra_app_client_secret>"}}'
export TF_VAR_origin_pull_certificates='{"api_origin":{"certificate":"<client_certificate_pem>","private_key":"<private_key_pem>"}}'
```

`.gitignore` enforces default-deny rules for `*.tfvars`, with explicit whitelisting for `layers/*/defaults.auto.tfvars` and `accounts/*/*.tfvars`. It explicitly re-denies `**/terraform.tfvars`, `**/local.auto.tfvars`, and `**/*.local.tfvars`.

## Pipeline Execution & Layer Mapping

Terraform is executed strictly within GitHub Actions CI/CD pipelines and never on local developer or operator workstations. The project must never be initialised or applied locally: credentials, scoped API tokens, and remote state keys reside exclusively within GitHub Environments protected by strict RBAC, mandatory reviews, and approval gates.

Plans and applies are dispatched by hand from the Actions tab. When one runs:
1. `tf-matrix.sh` selects every account and layer pair the `account` and `layer` inputs allow - the whole fleet by default - and sorts the layers into three apply tiers. (On a pull request, `ci.yml` uses the same script to pick pairs from the changed files for its offline plan.)
2. The pipeline runner initialises the target layer dynamically using remote backend flags, without hardcoding bucket configurations into version control.
3. `tf-varfiles.sh` resolves and supplies the exact `-var-file` arguments declared for that layer.
4. The plan runs in the `<account>-plan` environment with a read-only token and is saved as an immutable plan artifact. A value-free summary of resource addresses and actions goes to the job summary.
5. Upon human approval in the `<account>-<layer>-apply` environment, the apply workflow consumes the exact plan file produced in the planning stage.

### Layer Variable File Mapping

The pipeline maps variable files to layers dynamically. The table below lists the configuration files and sensitive environment variables consumed by each layer during automated execution:

| Layer                | Required `-var-file` Arguments                                        | Sensitive Environment Variables                                                                                               |
| ----------------------| -----------------------------------------------------------------------| -------------------------------------------------------------------------------------------------------------------------------|
| `account_governance` | `account.tfvars`, `account_governance.tfvars`                         | None                                                                                                                          |
| `bulk_redirects`     | `account.tfvars`, `zones.tfvars`, `bulk_redirects.tfvars`             | None                                                                                                                          |
| `device_posture`     | `account.tfvars`, `device_posture.tfvars`                             | `TF_VAR_device_posture_integration_secrets` (from the `<account>-plan` environment)                                           |
| `dns`                | `account.tfvars`, `zones.tfvars`, `dns.tfvars`                        | None                                                                                                                          |
| `gateway`            | `account.tfvars`, `gateway.tfvars`                                    | None                                                                                                                          |
| `lists`              | `account.tfvars`, `lists.tfvars`                                      | None                                                                                                                          |
| `load_balancing`     | `account.tfvars`, `zones.tfvars`, `load_balancing.tfvars`             | None                                                                                                                          |
| `logpush`            | `account.tfvars`, `zones.tfvars`, `logpush.tfvars`                    | `TF_VAR_logpush_destination_secrets`, `TF_VAR_logpush_ownership_challenges` (from the `<account>-plan` environment)           |
| `origin_pulls`       | `account.tfvars`, `zones.tfvars`, `origin_pulls.tfvars`               | `TF_VAR_origin_pull_certificates` (from the `<account>-plan` environment; only where a zone uploads a certificate of its own) |
| `pages`              | `account.tfvars`, `zones.tfvars`, `pages.tfvars`                      | `TF_VAR_pages_project_secrets` (from the `<account>-plan` environment; only where a project lists `secret_names`)             |
| `r2`                 | `account.tfvars`, `zones.tfvars`, `r2.tfvars`, `tags.tfvars`          | None                                                                                                                          |
| `rules`              | `account.tfvars`, `zones.tfvars`, `rules.tfvars`                      | None                                                                                                                          |
| `tunnels`            | `account.tfvars`, `zones.tfvars`, `tunnels.tfvars`                    | None (no tunnel secret is sent and no connector token is read)                                                                |
| `turnstile`          | `account.tfvars`, `turnstile.tfvars`                                  | None (Cloudflare issues the widget secret, and it lands in this layer's state)                                                |
| `waf`                | `account.tfvars`, `zones.tfvars`, `waf.tfvars`                        | None                                                                                                                          |
| `wan`                | `account.tfvars`, `wan.tfvars`                                        | `TF_VAR_wan_ipsec_tunnel_psks`, `TF_VAR_wan_bgp_md5_keys` (not yet exported by the pipeline)                                  |
| `workers`            | `account.tfvars`, `zones.tfvars`, `workers.tfvars`, `tags.tfvars`     | None (Worker secrets use Secrets Store)                                                                                       |
| `zerotrust`          | `account.tfvars`, `zerotrust.tfvars`, `tags.tfvars`                   | `TF_VAR_identity_provider_secrets` (from the `<account>-plan` environment; must be set, `{}` if none)                         |
| `zones`              | `account.tfvars`, `zones.tfvars`, `zone_config.tfvars`, `tags.tfvars` | None                                                                                                                          |

Like `zones.tfvars`, `tags.tfvars` reaches several layers: it assigns `resource_tags`, which `zones`, `zerotrust`, `r2` and `workers` each declare and each read their own section of. The layers resolve and output the tags; a pipeline job writes them after apply, because the provider has no tagging resource yet. See [Resource tags](../.github/workflows/README.md#resource-tags).

### Remote state

State is stored in Cloudflare R2 using the S3-compatible backend.

The backend configuration block is committed commented out so that automated CI linting jobs can execute offline validation (`terraform init -backend=false`) in container runners without cloud credentials. In deployment pipelines, the runner injects the backend configuration dynamically at runtime:

```bash
terraform init -reconfigure \
  -backend-config="bucket=<state-bucket>" \
  -backend-config="key=account_a/zones.tfstate" \
  -backend-config="endpoints={s3=\"https://<state-account-id>.r2.cloudflarestorage.com\"}"
```

**State Locking:** Because R2 does not provide a DynamoDB lock table alternative, concurrent applies against the same state key can cause state corruption. Setting `use_lockfile = true` enables native S3 conditional writes, which R2 supports.

This feature requires Terraform 1.11.0 or newer. Every layer enforces `required_version = ">= 1.12.0"`, which covers it: the floor is 1.12 because the modules rely on `||` and `&&` short-circuiting. Either way, an older Terraform cannot silently run an unlocked apply. The CI/CD pipeline pins Terraform 1.14.6.

Pipeline concurrency groups serialise runs per state key as an additional safeguard.

## Referring to other resources

Resources reference each other by logical key, never by physical Cloudflare ID. A WAF policy specifies `zone_key = "primary"`, which the layer resolves to a zone ID. Logical keys represent permanent identity: renaming a key causes Terraform to destroy and recreate the underlying resource.

Keys are scoped locally to each account tree: `primary` in `account_a` is completely independent of `primary` in `account_b`.

`preflight.tf` in each layer enforces structural guardrails at plan time:
- A `zone_key` referencing an unmanaged zone fails the plan with an explicit error.
- A `zone_config` entry referencing an undeclared zone fails the plan.
- Two WAF policies conflicting over the same zone are caught before apply.
- A load balancer hostname outside its zone domain fails the plan.
- An R2 bucket configured for public anonymous `.r2.dev` access fails the plan.
- A queue with no consumer, a consumer with no dead letter queue, or a queue that dead letters into itself fails the plan.
- A D1 database restricted to a jurisdiction while carrying read replication fails the plan.
- A Cloudflare WAN static route pointing to an unmanaged tunnel fails the plan.
- A Cloudflare Tunnel hostname outside its referenced zone, or a tunnel route naming an undeclared tunnel, fails the plan.
- A zone-scoped Logpush job on a zone below Enterprise, a dataset pushed from the wrong scope, or a credential committed in a Logpush destination fails the plan.
- A user group assigning an undeclared member fails the plan.
- An unmanaged root CA certificate or uninspected HTTP rule in Gateway fails the plan.
- A firewall posture check that passes a disabled firewall, a binary check with no signing thumbprint, a posture result that expires before it is refreshed, or a service provider integration missing its credential fails the plan.

---

## Zones

The `zones` layer manages zone lifecycle, rate plan subscriptions, TLS security settings, and baseline bot management.

```hcl
# accounts/account_a/zones.tfvars
zones = {
  primary = {
    domain_name = "example.com"
    zone_tier   = "business"
  }
  internal = {
    domain_name = "example.net"
  }
}
```

```hcl
# accounts/account_a/zone_config.tfvars
zone_config = {
  primary = {
    ssl_mode         = "strict"
    min_tls_version  = "1.2"
    always_use_https = "on"
    security_level   = "medium"
  }
}
```

### Governing defaults

| Setting | Default | Effect |
|---|---|---|
| `default_ssl_mode` | `"strict"` | Requires valid SSL certificates on origins. Prevents interception between Cloudflare edge and origin. |
| `default_min_tls_version` | `"1.2"` | Rejects legacy TLS 1.0 and 1.1 connections edge-wide. |
| `default_tls_1_3` | `"on"` | Enables TLS 1.3 without 0-RTT by default (0-RTT requires idempotent origins). |
| `default_always_use_https` | `"on"` | Automatically redirects HTTP requests to HTTPS with a 301 redirect. |
| `manage_zone_subscriptions` | `false` | Billing safeguard. When false, Terraform will not modify zone subscription plans. Set to true only when Terraform is authorised to purchase paid rate plans. |
| `default_subscription_frequency` | `"monthly"` | Subscription billing frequency (`monthly` or `annual`). |

---

## DNS

The `dns` layer manages DNS records independently of zone containers. Isolating DNS records into its own layer prevents routine record updates from introducing drift or risk to zone settings.

```hcl
# accounts/account_a/dns.tfvars
dns_config = {
  primary = {
    dns_records = [
      { name = "@", type = "A", content = "203.0.113.10", ttl = 1, proxied = true },
      { name = "www", type = "CNAME", content = "example.com", ttl = 1, proxied = true },
      { name = "@", type = "MX", content = "mail.example.com", ttl = 3600, priority = 10 },
      { name = "@", type = "TXT", content = "v=spf1 include:_spf.example.com -all", ttl = 3600 },
      { name = "_dmarc", type = "TXT", content = "v=DMARC1; p=reject; rua=mailto:dmarc@example.com", ttl = 3600 },
    ]
  }
}
```

### Key Considerations
- `proxied = true` requires `ttl = 1` (automatic TTL). Proxying is supported only on `A`, `AAAA`, and `CNAME` records.
- Names can be specified as `"@"`, relative (`"www"`), or fully qualified (`"www.example.com"`). The module normalises them automatically. Declaring both relative and fully qualified variations of the same record causes a plan validation failure.
- Cloudflare-managed records (such as R2 custom domain CNAMEs) are not declared in `dns.tfvars`. The DNS module manages only declared resources and will not prune unmanaged records.

---

## WAF Baseline

The `waf` layer manages custom firewall rules, rate limiting, and managed ruleset associations. Operators select baseline security policies by name rather than writing complex wirefilter expressions manually.

```hcl
waf_policies = {
  primary = {
    zone_key              = "primary"
    baseline_custom_rules = ["block_admin_from_untrusted", "block_known_exploit_paths"]
    baseline_rate_limits  = ["auth_brute_force", "api_general"]
  }
}
```

The baseline catalogue is defined in `layers/waf/locals.waf.tf` and parameterised via variables (`waf_trusted_ip_ranges`, `waf_admin_paths`, `waf_blocked_countries`).

### Custom rules

| Name | Action | Requires |
|---|---|---|
| `block_admin_from_untrusted` | `block` | `waf_trusted_ip_ranges` |
| `geoblock_countries` | `block` | `waf_blocked_countries` |
| `block_known_exploit_paths` | `block` | None |
| `challenge_undisclosed_bots` | `managed_challenge` | `waf_trusted_ip_ranges` |
| `log_trusted_admin_access` | `log` | `waf_trusted_ip_ranges` |

### Rate limits

| Name | Mitigation | Notes |
|---|---|---|
| `auth_brute_force` | `block` | 20 req/min per IP on login and authentication paths. |
| `api_general` | `managed_challenge` | 600 req/min per IP under `/api/`. |
| `origin_error_shield` | `block` | Evaluates origin 5xx responses. |
| `observe_only` | `log` | Measures traffic before enforcement. Forces `mitigation_timeout = 0`. |

**Automatic Colocation Characteristic:** Cloudflare tracks zone-level rate limits per data centre colocation, rejecting rate limiting rules that omit `cf.colo.id` (API error 20155). The layer automatically appends `cf.colo.id` to all rate limiting rules, eliminating manual configuration errors.

**Rule Evaluation Order:** Baseline platform rules are concatenated ahead of tenant-specific custom rules. Cloudflare processes rules sequentially, guaranteeing that platform security blocks cannot be bypassed by custom tenant rules.

**Validation Guardrails:** Baseline rules with empty input variables fail the plan immediately. For example, enabling `block_admin_from_untrusted` with an empty `waf_trusted_ip_ranges` would generate a rule blocking all admin access globally, including internal operations.

---

## Account Governance

The `account_governance` layer manages account-level membership, user groups, and role-based access control (RBAC). Changes here affect who can access the Cloudflare dashboard.

```hcl
account_members = {
  dns_operator = { email = "dns.operator@example.com" }
}

user_groups = {
  dns_operators = {
    name        = "DNS Operators"
    member_keys = ["dns_operator"]
    policies = [
      { permission_group_names = ["DNS Write", "Zone Read"] },
    ]
  }
}
```

Role, permission group, and resource group IDs are account-specific. The layer dynamically resolves human-readable names to IDs at plan time (`permission_lookup.tf`). An invalid role or permission name triggers an informative plan failure listing available roles in the account.

### Governing defaults

| Setting | Default | Effect |
|---|---|---|
| `default_role_names` | `["Minimal Account Access"]` | Members without an explicit role receive minimal dashboard access. Permissions are granted predictably through user groups. |
| `restricted_role_names` | `["Super Administrator - All Privileges"]` | Fails the plan if this role is requested by name or ID. Granting Super Administrator requires an explicit exception. |
| `allowed_email_domains` | `[]` (any) | Restricts member invitations to corporate email domains. Mistyped external addresses fail at plan time. |

### Out of Scope
- **API Tokens:** API tokens represent credentials and must never enter Terraform state.
- **Account Resource:** The layer manages memberships and groups, but does not own the account resource itself.

---

## R2

The `r2` layer provisions object storage buckets, CORS configurations, lifecycle rules, object retention locks, and custom domains.

```hcl
r2_buckets = {
  public_assets = {
    name = "account-a-public-assets"

    cors_rules = [
      {
        allowed_origins = ["https://app.example.com"]
        allowed_methods = ["GET", "HEAD"]
        max_age_seconds = 3600
      },
    ]

    lifecycle_rules = [
      { id = "expire-raw", prefix = "raw/", delete_objects_after_days = 30 },
    ]

    custom_domains = [
      { zone_key = "primary", hostname = "assets.example.com" },
    ]
  }
}
```

### Provider 5.x Native Resources
Older Cloudflare Terraform patterns used the AWS provider for R2 bucket lifecycles and CORS. This layer relies exclusively on native Cloudflare provider resources (`cloudflare_r2_bucket_cors`, `cloudflare_r2_bucket_lifecycle`, `cloudflare_r2_custom_domain`). This eliminates the need to store data-plane S3 access keys in pipeline environments.

### Governing defaults

| Setting | Default | Effect |
|---|---|---|
| `allow_public_r2_dev_domains` | `false` | Fails the plan if a bucket requests an unauthenticated, uncached `pub-<hash>.r2.dev` public URL. Public assets should be served via `custom_domains` behind Cloudflare cache and WAF. |
| `allow_wildcard_cors_origins` | `false` | Fails the plan if `allowed_origins = ["*"]` is specified, preventing unauthorised cross-origin data exposure. |
| `allow_bucket_wide_object_expiry` | `false` | Fails the plan if a lifecycle rule specifies an empty prefix, preventing accidental fleet-wide object deletion. |
| `default_custom_domain_min_tls` | `"1.2"` | Enforces TLS 1.2 minimum on custom domain endpoints. |

---

## Zero Trust

The `zerotrust` layer manages Cloudflare Access: team domain adoption, identity provider integrations, access groups, service tokens, and access applications.

```hcl
access_groups = {
  platform_engineers = {
    name = "Platform Engineers"
    include = {
      entra_groups = [
        { identity_provider_key = "entra_id", group_id = "<entra_group_object_id>" },
      ]
    }
  }
}

access_policies = {
  platform_engineers_mfa = {
    name     = "Platform Engineers with MFA"
    decision = "allow"
    include  = { group_keys = ["platform_engineers"] }
    require  = { auth_methods = ["mfa"] }
  }
}

access_applications = {
  grafana = {
    name        = "Grafana"
    domain      = "grafana.example.com"
    policy_keys = ["platform_engineers_mfa"]
  }
}
```

### Team Name Management
A Cloudflare Zero Trust organisation must exist before Access resources can be provisioned. Setting `zero_trust_team_name` adopts and manages the organisation. If left unset, the layer adopts the team name already provisioned on the account. Renaming an existing team domain breaks active Access URLs and WARP registrations, so `allow_team_name_change` must be explicitly set to authorise renames.

### Secrets Injection
Identity provider client secrets (such as Microsoft Entra ID application registration secrets) must never be committed to `.tfvars` files. They are supplied at plan time, keyed by identity provider, from the `<account>-plan` environment's `TF_VAR_IDENTITY_PROVIDER_SECRETS`. The pipeline exports it on every plan, so it must be set whenever this layer is planned - to `{}` on an account with no identity provider secrets:

```bash
export TF_VAR_identity_provider_secrets='{"entra_id":"<the_secret>"}'
```

Service token secrets are generated by Cloudflare and stored in state. They are deliberately omitted from Terraform plan outputs to prevent credential disclosure in pull requests.

### Governing defaults

| Setting | Default | Effect |
|---|---|---|
| `restricted_policy_decisions` | `["bypass"]` | Fails the plan if an Access policy uses `bypass`, which removes authentication entirely. |
| `allowed_email_domains` | `[]` (any) | Restricts allowed email domains in policy rules. |
| `lock_dashboard_to_read_only` | `false` | When enabled, locks the Zero Trust dashboard to read-only, establishing GitOps as the sole modification route. |
| `default_session_duration` | `"24h"` | Default session lifespan before re-authentication is required. |
| `default_service_token_duration` | `"8760h"` | One-year lifespan for service tokens. Prevents unrotated perpetual tokens. |

---

## Device Posture

The `device_posture` layer manages the checks a device must pass before an Access or Gateway policy lets it through - Cloudflare One Client checks run on the device (client running, OS version, disk encryption, firewall, a signed EDR binary, a corporate serial number) - and the service provider integrations that read a verdict from an MDM or EDR: Intune, CrowdStrike, SentinelOne, Kolide, Tanium, Workspace ONE, Uptycs or a custom API.

It is deliberately separate from `zerotrust`. Two layers consume a posture rule - Access policies in `zerotrust` and Gateway policies in `gateway` - and applying it in Tier 2 means a rule exists before either names it. It also keeps the MDM and EDR credentials out of `zerotrust` state, which already holds identity provider secrets and service tokens.

```hcl
# accounts/account_a/device_posture.tfvars
device_posture_rules = {
  require_client = { name = "Cloudflare One Client Running", type = "warp" }

  windows_supported_build = {
    name      = "Windows 11 23H2 or Later"
    type      = "os_version"
    platforms = ["windows"]
    input     = { operating_system = "windows", operator = ">=", version = "10.0.22631" }
  }

  intune_compliant = {
    name            = "Intune Compliant"
    type            = "intune"
    integration_key = "intune"
    input           = { compliance_status = "compliant" }
  }
}

device_posture_integrations = {
  intune = {
    name   = "Microsoft Intune"
    type   = "intune"
    config = { client_id = "<application id>", customer_id = "<tenant id>" }
  }
}
```

### Referencing a Rule
Neither consuming layer can read this layer's state, so a rule is referenced by ID: apply it, read `device_posture_rule_ids` from this layer's outputs, and put the ID in `device_posture_ids` (`zerotrust.tfvars`) or `device_posture_check_ids` (`gateway.tfvars`).

Renaming a rule replaces it and changes its ID. Removing one that a policy still names leaves the policy requiring a check nothing can pass - and because this layer applies first, removing both in one run deletes the rule before the policy stops naming it. Remove the reference, apply, then remove the rule.

### Secrets Injection
An integration's credential never goes in `.tfvars`. It is supplied at plan time, keyed by integration, from the `<account>-plan` environment's `TF_VAR_DEVICE_POSTURE_INTEGRATION_SECRETS`:

```bash
export TF_VAR_device_posture_integration_secrets='{"intune":{"client_secret":"<entra_app_client_secret>"}}'
```

The plan fails for an integration missing a setting or credential its type needs, and for a credential no integration reads. Cloudflare tests the connection on create, so a wrong credential still fails at apply. The example account trees keep their integrations commented out, because CI plans this layer offline with no secrets.

### Governing defaults

| Setting                         | Default      | Effect                                                                                                                                                                                         |
| ---------------------------------| --------------| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `default_posture_schedule`      | `"5m"`       | Client re-check interval, stated explicitly as Cloudflare's own default.                                                                                                                       |
| `default_integration_interval`  | `"10m"`      | How often Cloudflare polls a service provider.                                                                                                                                                 |
| `derive_posture_expiration`     | `true`       | A rule with no expiration gets twice its polling period. Without one, a device that stops reporting keeps its last pass indefinitely. An explicit expiration shorter than that fails the plan. |
| `require_signed_binary_checks`  | `true`       | Fails the plan for a file or application check with no signing thumbprint, which any file at that path would pass.                                                                             |
| `restricted_posture_rule_types` | `["tanium"]` | Refuses the legacy Access-only Tanium check, which Gateway cannot evaluate.                                                                                                                    |

A firewall check with `enabled = false` always fails the plan: it passes only devices whose firewall is off.

### Out of Scope
- **Zero Trust lists:** the serial number or device ID list a `serial_number` or `unique_client_id` check reads is maintained outside Terraform, and referenced by `list_id`.
- **Client certificates:** the signing certificate a `client_certificate_v2` check validates against is uploaded separately, and referenced by `certificate_id`.
- **WARP client deployment and device profiles.**

---

## Cloudflare Tunnel

The `tunnels` layer manages Cloudflare Tunnels: outbound-only `cloudflared` connectors that publish origins on a private network without opening an inbound port, the proxied DNS record behind each published hostname, and the private network routes and virtual networks WARP clients reach through a tunnel.

It is deliberately separate from `zerotrust`. Access decides *who* may reach an application; a tunnel decides *what* is reachable at all. Separate state and separate tokens mean an Access policy change cannot delete a tunnel, and a tunnel change cannot loosen a policy.

```hcl
# accounts/account_a/tunnels.tfvars
cloudflare_tunnels = {
  london_dc = {
    name = "lon-dc-01"
    ingress = [
      { hostname = "grafana.example.com", zone_key = "primary", path = "^/api/", service = "http://grafana-api.internal:3000" },
      { hostname = "grafana.example.com", zone_key = "primary", service = "http://grafana.internal:3000" },
    ]
  }
  manchester_dc = { name = "man-dc-01" }
}

tunnel_virtual_networks = {
  manchester = { name = "man-dc" }
}

tunnel_routes = {
  london_servers     = { network = "172.16.10.0/24", tunnel_key = "london_dc" }
  manchester_servers = { network = "172.16.10.0/24", tunnel_key = "manchester_dc", virtual_network_key = "manchester" }
}
```

### Public Hostnames
Ingress rules are evaluated in order and the first match wins, so a path-specific rule goes above the bare hostname it narrows. A catch-all rule (`default_catch_all_service`, a 404 by default) is appended automatically, because `cloudflared` requires the last rule to match everything.

Every rule with a `zone_key` gets its proxied CNAME (`<tunnel-id>.cfargotunnel.com`) created in that zone by this layer, in the same apply as the tunnel, so a hostname cannot exist without the record that routes to it. Do not also declare that record in `dns.tfvars`: Cloudflare refuses a second record of the same name.

A published hostname is reachable by anybody on the internet unless an Access application in `zerotrust` covers it. This layer cannot see that layer's state, so it cannot check. Pair every hostname with an application there, and set `origin_request.access` so `cloudflared` also validates the Access token at the origin.

### Connector Tokens
No tunnel secret is sent, so Cloudflare generates one it never returns, and the layer never reads the connector token. State and outputs hold nothing that can run a connector, and the `tunnels` environment carries no `TF_VAR_` secret. Fetch a token when installing a connector - from the dashboard, `cloudflared tunnel token <tunnel-id>`, or `GET /accounts/<account_id>/cfd_tunnel/<tunnel_id>/token` - and deliver it to the host through a secret store. A tunnel shows `inactive` until a connector runs.

Redundancy is more connectors on one tunnel, not more tunnels: run `cloudflared` with the same token on a second host.

### Out of Scope
- **Running `cloudflared`:** connectors are deployed on the origin network by whatever manages those hosts.
- **Who may use a route:** a private network route makes a range reachable by an enrolled device. Restricting it to people is a Gateway network policy or an Access application with a private destination.

### Governing defaults

| Setting | Default | Effect |
|---|---|---|
| `default_tunnel_config_src` | `"cloudflare"` | Remotely managed: the ingress rules here are what every connector runs, and a dashboard edit shows up as drift. |
| `default_catch_all_service` | `"http_status:404"` | Unmatched requests get a 404 rather than falling through to a real service. |
| `allow_no_tls_verify` | `false` | Fails the plan if an origin setting disables certificate verification. Use `ca_pool` or `origin_server_name` instead. |
| `allow_unmanaged_tunnel_hostnames` | `false` | Fails the plan if an ingress rule has no `zone_key`, since nothing would route the hostname to the tunnel. |
| `allow_default_tunnel_route` | `false` | Prohibits `0.0.0.0/0` or `::/0` tunnel routes, which would make one connector the internet egress for every WARP device. |
| `allow_public_tunnel_route_prefixes` | `false` | Restricts tunnel routes to RFC 1918, RFC 6598 or IPv6 ULA ranges. |

---

## Logpush

The `logpush` layer manages Logpush jobs: one dataset, pushed from an account or a zone, to one destination - a SIEM, an HTTP endpoint or an object store. It is how Cloudflare's logs leave Cloudflare: the account audit trail, Gateway and Access activity, and every HTTP request and firewall event on a zone.

> **Enterprise only.** Cloudflare refuses a Logpush job on any other plan. On an account without it, leave `logpush_jobs = {}`.

```hcl
# accounts/account_a/logpush.tfvars
logpush_jobs = {
  audit_archive = {
    dataset = "audit_logs"
    # No destination_conf: an R2 URI carries its access key, so it arrives in TF_VAR_logpush_destination_secrets
    output_options = {
      field_names = ["When", "ActionType", "ActorEmail", "ActorIP", "ResourceType", "ResourceID"]
    }
  }

  primary_http_requests = {
    dataset          = "http_requests"
    zone_key         = "primary"
    destination_conf = "s3://example-com-logs/http_requests/{DATE}?region=eu-west-2&sse=AES256"
    filter = <<-JSON
      {"where":{"and":[{"key":"ClientRequestPath","operator":"!eq","value":"/healthz"}]}}
    JSON
    output_options = {
      field_names = ["EdgeStartTimestamp", "RayID", "ClientIP", "ClientRequestHost", "ClientRequestURI", "EdgeResponseStatus"]
    }
  }
}
```

### Scope
Each dataset is produced per zone (`http_requests`, `dns_logs`, ...) or per account (`audit_logs`, `gateway_dns`, `access_requests`, ...), and a few, such as `firewall_events`, at both. A job for a zone dataset names a `zone_key`; a job for an account dataset does not. The catalogue that decides which is `logpush_zone_datasets` and `logpush_account_datasets` in `layers/logpush/variables.tf`, and a job in the wrong scope fails the plan rather than the apply.

A zone-scoped job also needs its zone on Enterprise. The layer reads `zone_tier` from `zones.tfvars` and fails the plan below `logpush_min_zone_tier`, so declare the zone's real plan there.

`output_options.field_names` is required on every job. Cloudflare has no "all fields" option, and each dataset's page in the Logpush documentation lists its fields.

### Destinations and Secrets
A destination with no credential in its URI - S3, Google Cloud Storage - is committed as `destination_conf`. One that carries a credential - R2 access keys, a Splunk HEC token, a Datadog API key, an Azure SAS, an HTTP auth header - is not: the job leaves `destination_conf` out, and the whole URI is supplied at plan time, keyed by job:

```bash
export TF_VAR_logpush_destination_secrets='{"audit_archive":"r2://<bucket>/audit/{DATE}?account-id=<id>&access-key-id=<key_id>&secret-access-key=<secret>"}'
```

The plan fails on a credential-shaped `destination_conf` in a `.tfvars`, on a job with neither or both, and on a secret keyed to no job.

Where Cloudflare asks for proof of control before it will push - object stores such as S3 and Google Cloud Storage - it writes a challenge file into the destination, and the file's contents go in `TF_VAR_logpush_ownership_challenges` under the job's key.

Both are read by the plan, so the pipeline takes them from the `<account>-plan` environment (`TF_VAR_LOGPUSH_DESTINATION_SECRETS`, `TF_VAR_LOGPUSH_OWNERSHIP_CHALLENGES`), not the apply one. Both reach state and the saved plan in plain text.

### Governing defaults

| Setting | Default | Effect |
|---|---|---|
| `default_logpush_job_enabled` | `true` | A declared job pushes. The provider's own default is disabled, which looks configured and ships nothing. |
| `default_logpush_timestamp_format` | `"rfc3339"` | Parsed by every SIEM without a custom rule, and what a dashboard-built job uses. The API's own default is `unixnano`. |
| `default_logpush_output_type` | `"ndjson"` | One record format across every job. |
| `default_cve_2021_44228_redaction` | `true` | Rewrites `${` to `x{` in the output, so a Log4Shell lookup string a client sent never reaches a downstream log processor intact. |
| `logpush_min_zone_tier` | `"enterprise"` | Fails the plan for a zone-scoped job on a lower plan, which Cloudflare would refuse at apply. |
| `required_logpush_account_datasets` | `[]` | Account datasets every account must push, e.g. `["audit_logs"]`. Empty by default because Logpush is Enterprise-only. |
| `allow_logpush_sampling` | `false` | Fails the plan if a job samples its output. A sampled log drops the event that matters as readily as any other. |
| `allow_insecure_logpush_destinations` | `false` | Fails the plan for a plain `http://` destination or `insecure-skip-verify=true`, checked against secret destinations too. |

### Out of Scope
- **The destination itself:** buckets, bucket policies, SIEM indexes and HEC tokens are created where they live. An R2 log bucket can come from the `r2` layer; its access key cannot, by design.
- **Ownership challenge automation:** the token is read out of the destination, which this layer holds no credential for.

---

## Gateway (Secure Web Gateway)

The `gateway` layer manages outbound corporate egress filtering: DNS policies, network L4 policies, HTTP L7 inspection rules, account-level Gateway settings, and automated root CA certificate lifecycle.

### Three Enforcement Pipelines

| Pipeline | Inspection Point | Visibility Scope | Typical Actions |
|---|---|---|---|
| `dns` | Resolves query prior to connection | Hostname only. Blind to payload or path | `allow`, `block`, `override`, `safesearch` |
| `network` | L4 connection (TCP/UDP/ICMP) | Ports, IP addresses, TLS SNI | `allow`, `block`, `l4_override` |
| `http` | Decrypted L7 HTTP/HTTPS traffic | Full URL path, query strings, headers, body | `allow`, `block`, `off`, `scan`, `isolate`, `quarantine` |

### Precedence Architecture
Gateway evaluates policies in ascending precedence order within each pipeline and stops on the first match. Lower precedence numbers execute first.

Precedence numbers below `reserved_precedence_ceiling` (default `100`) are strictly reserved for platform baseline policies. Custom rules in account configuration must specify precedence values of 100 or higher, with recommended intervals of 100 to permit future rule insertion.

```hcl
gateway_policies = {
  allow_sanctioned_smtp = {
    name       = "Allow Sanctioned SMTP Relay"
    type       = "network"
    action     = "allow"
    precedence = 100
    match = {
      destination_ip_cidrs = ["203.0.113.25/32"]
      destination_ports    = [587]
      protocols            = ["tcp"]
    }
  }

  block_direct_smtp = {
    name       = "Block Direct Outbound SMTP"
    type       = "network"
    action     = "block"
    precedence = 200
    match      = { destination_ports = [25, 465, 587], protocols = ["tcp"] }
  }
}
```

### Account Settings & TLS Decryption
The `gateway_settings` object configures account-wide Gateway posture:
- `tls_decrypt.enabled`: Controls whether Gateway intercepts and decrypts outbound HTTPS connections.
- `protocol_detection.enabled`: Identifies protocols from packet contents rather than relying solely on destination ports.
- `antivirus`: Configures scanning of uploaded and downloaded files.

```hcl
gateway_settings = {
  tls_decrypt        = { enabled = true }
  protocol_detection = { enabled = true }
  activity_log       = { enabled = true }
  antivirus = {
    enabled_download_phase = true
    enabled_upload_phase   = true
    fail_closed            = false
  }
}

gateway_inspection_certificate = {
  validity_period_days = 1826 # 5 years
}
```

### Automated Root CA Lifecycle
Enabling TLS decryption without an active root CA certificate causes Cloudflare API error 400 (code 2211). Setting `gateway_inspection_certificate` generates and edge-activates a custom root CA certificate automatically, linking it directly to `gateway_settings`.

Before activating `tls_decrypt.enabled`, distribute this CA certificate to all managed endpoints (via Microsoft Intune, Group Policy, or MDM) to prevent untrusted certificate warnings across user devices.

### Microsoft 365 Decryption Bypass
Certain enterprise applications (such as Microsoft 365 desktop clients) use certificate pinning and fail under TLS decryption. The platform baseline provides a preconfigured bypass rule:

```hcl
gateway_baseline_policies   = ["bypass_trusted_applications"]
gateway_bypass_applications = ["Microsoft 365"]
```

Cloudflare processes Do Not Inspect (`action = "off"`) rules before evaluating inspection-dependent policies.

### Governing defaults

| Setting | Default | Effect |
|---|---|---|
| `reserved_precedence_ceiling` | `100` | Reserves precedence 1 to 99 for platform baseline rules. Custom policies claiming lower precedence fail at plan time. |
| `allow_antivirus_fail_closed` | `false` | Fails the plan if antivirus `fail_closed` is enabled without explicit authorisation. Unscannable or oversized files are delivered rather than causing widespread unexplained download failures. |
| `allow_uninspected_http_policies` | `false` | Fails the plan if HTTP policies exist whilst `tls_decrypt.enabled` is false. Prevents false security assumptions where L7 rules would only apply to unencrypted HTTP. |
| `allow_dlp_payload_logging` | `false` | Prevents sensitive matching data from being recorded in logs. |
| `allow_disabling_dnssec_validation` | `false` | Enforces DNSSEC validation on all DNS queries. |
| `allow_untrusted_certificate_pass_through` | `false` | Rejects connections to origins with invalid SSL certificates. |

---

## Cloudflare WAN

The `wan` layer manages Magic WAN: IPsec and GRE tunnels connecting customer premises, data centres, and cloud VPCs to Cloudflare Anycast edge, alongside static routing.

```hcl
wan_ipsec_tunnels = {
  london_primary = {
    name                = "lon-ipsec-01"
    cloudflare_endpoint = "192.0.2.10"
    customer_endpoint   = "203.0.113.10"
    interface_address   = "10.252.0.0/31"
  }
}

wan_static_routes = {
  london_lan = {
    prefix     = "10.10.0.0/16"
    tunnel_key = "london_primary"
    priority   = 100
  }
}
```

### Derived Next Hops
In a `/31` tunnel interface, Cloudflare occupies one IP address and the customer edge router occupies the other. Static routes must target the customer router as the next hop. The layer derives customer next-hop IP addresses automatically from `tunnel_key`, preventing configuration errors that route traffic into Cloudflare's own endpoint.

### Secrets Injection
IPsec Pre-Shared Keys (PSKs), and BGP MD5 keys where a tunnel peers, must never be stored in `.tfvars`. They are supplied as `TF_VAR_wan_ipsec_tunnel_psks` and `TF_VAR_wan_bgp_md5_keys`. The pipeline does not export either yet: add a conditional export to the plan step of `_terraform-run.yml` and hold the secrets in `<account>-plan` - see [.github/workflows/README.md](../.github/workflows/README.md).

```bash
export TF_VAR_wan_ipsec_tunnel_psks='{"london_primary":"<32_char_secure_psk>"}'
```

### Governing defaults

| Setting | Default | Effect |
|---|---|---|
| `allow_tunnels_without_health_checks` | `false` | Enforces bidirectional health checks on every tunnel to ensure automated failover. |
| `allow_single_tunnel_prefixes` | `false` | Requires at least two redundant tunnels for each advertised prefix. |
| `allow_default_static_route` | `false` | Prohibits default `0.0.0.0/0` or `::/0` routes into site tunnels. |
| `allow_public_static_route_prefixes` | `false` | Restricts static routes to private RFC 1918, RFC 6598, or IPv6 ULA ranges. |

---

## Lists

The `lists` layer manages account-scoped Cloudflare Lists: reusable collections of IP addresses, CIDR blocks, ASNs, or hostnames referenced across WAF and firewall rules as `$name`.

```hcl
# accounts/account_a/lists.tfvars
account_lists = {
  global_ip_blocklist = {
    name         = "corp_global_ip_blocklist"
    kind         = "ip"
    description  = "Operationally managed IP blocklist"
    manage_items = false
  }
  partner_egress_ips = {
    name         = "partner_egress_ips"
    kind         = "ip"
    description  = "Trusted partner static egress ranges"
    manage_items = true
    items = [
      { value = "198.51.100.0/24", comment = "Partner Primary DC" },
      { value = "203.0.113.50/32", comment = "Partner Secondary Gateway" },
    ]
  }
}
```

### Operational vs Managed Items
- `manage_items = false`: Terraform provisions and manages the list container itself. List items are added or removed dynamically via the Cloudflare dashboard, SIEM integrations, or SOC automated response scripts without triggering Terraform state drift.
- `manage_items = true`: Terraform manages list rows authoritatively. Any out-of-band changes are reverted on the next apply. Recommended for stable corporate address allocations.

`lists` is applied in Tier 2 so that named list objects are established before `waf` rules reference them in Tier 3.

---

## Rules

The `rules` layer manages zone-level traffic modification phases: Cache Rules (`http_request_cache_settings`), Transform Rules (`http_request_late_transform`), and Origin Rules (`http_request_origin`).

```hcl
# accounts/account_a/rules.tfvars
rule_policies = {
  primary = {
    zone_key = "primary"

    cache_rules = [
      {
        name        = "Cache anonymous static content"
        description = "Cache static assets ignoring query parameters for anonymous visitors"
        expression  = "not http.cookie contains \"session_id\""
        enabled     = true
        cache       = true
        cache_key = {
          custom_key = {
            query_string = { exclude = { all = true } }
          }
        }
      },
      {
        name       = "Bypass cache for authenticated API calls"
        expression = "http.request.uri.path contains \"/api/\""
        cache      = false
      },
    ]

    transform_rules = [
      {
        name       = "Strip untrusted client headers"
        expression = "true"
        enabled    = true
        headers = {
          "X-Forwarded-Host" = { operation = "remove" }
        }
      },
    ]

    origin_rules = [
      {
        name       = "Route legacy API to alternate backend"
        expression = "http.request.uri.path starts_with \"/api/v1/\""
        enabled    = true
        origin = {
          host = "legacy-api.internal.example.com"
          port = 8443
        }
      },
    ]
  }
}
```

### Phase Evaluation Semantics
Rule evaluation behaviour differs by phase:
- **Cache Rules:** Cloudflare evaluates all matching rules and the **last** matching rule takes precedence. Broad caching rules should be placed first, followed by specific bypass exceptions.
- **Origin Rules:** Cloudflare evaluates rules in order and stops at the **first** match. Specific overrides must precede general rules.
- **Transform Rules:** Evaluated in the late transform phase after security filtering, preventing spoofed request headers from bypassing WAF evaluation.

---

## Bulk Redirects

The `bulk_redirects` layer manages high-volume URL redirection at the Cloudflare edge, executing redirects before requests reach origin servers or Worker invocations.

```hcl
# accounts/account_a/bulk_redirects.tfvars
bulk_redirect_lists = {
  vanity_urls = {
    name         = "redirects_vanity_urls"
    description  = "Static marketing vanity redirects"
    manage_items = true
    items = [
      {
        source_url            = "example.com/legacy-docs"
        target_url            = "https://example.com/documentation"
        status_code           = 301
        preserve_query_string = true
      },
      {
        source_url            = "www.example.com/promo"
        target_url            = "https://www.example.com/promotions"
        status_code           = 302
        subpath_matching      = true
        preserve_path_suffix  = true
      },
    ]
  }
}

bulk_redirect_rules = [
  {
    list_key        = "vanity_urls"
    description     = "Apply vanity redirect list"
    scope_zone_keys = ["primary"]
  },
]
```

### Operational Considerations
- **Status Codes:** Use 302 (temporary) redirects during active testing or initial migration phases. Browsers cache 301 (permanent) redirects aggressively, making routing corrections difficult to propagate quickly.
- **Scope Restriction:** Scope redirect rules to specific zones using `scope_zone_keys` to limit blast radius.
- **Dataset Scalability:** For datasets containing thousands of entries, leave `manage_items = false` and load redirect rows asynchronously via the Cloudflare Bulk Redirects API or pipeline scripts.

---

## Workers, KV, D1 & Queues

The `workers` layer manages Cloudflare Workers scripts, Workers KV namespaces, D1 databases, queues, script bindings, routes, custom domains, and cron triggers.

```hcl
# accounts/account_a/workers.tfvars
kv_namespaces = {
  config = {
    title = "account-a-config"
  }
}

worker_scripts = {
  security_headers = {
    name        = "security-headers-worker"
    script_file = "headers/security_headers.js"

    bindings = [
      {
        name             = "CONFIG"
        type             = "kv_namespace"
        kv_namespace_key = "config"
      },
      {
        name        = "API_SECRET"
        type        = "secrets_store_secret"
        store_id    = "0123456789abcdef0123456789abcdef"
        secret_name = "telemetry-api-key"
      },
    ]

    routes = [
      {
        zone_key = "primary"
        pattern  = "example.com/*"
      },
    ]
  }
}
```

### Serverless State: D1 & Queues

D1 databases and queues are declared in the same file and bound by logical key, so no account tree carries a database UUID or a queue ID.

```hcl
# accounts/account_a/workers.tfvars
d1_databases = {
  telemetry = {
    name                  = "account-a-telemetry"
    primary_location_hint = "weur"
  }
}

queues = {
  telemetry = {
    name = "account-a-telemetry"

    consumer = {
      worker_key            = "telemetry_processor"
      dead_letter_queue_key = "telemetry_dlq"

      settings = {
        batch_size       = 50
        max_wait_time_ms = 5000
        max_retries      = 3
        retry_delay      = 30
      }
    }
  }

  # Holding pen for batches that failed three times. Exempt from
  # allow_queues_without_consumer because another queue dead letters into it.
  telemetry_dlq = {
    name                     = "account-a-telemetry-dlq"
    message_retention_period = 1209600
  }
}

worker_scripts = {
  telemetry_processor = {
    name        = "account-a-telemetry-processor"
    script_file = "queues/telemetry_processor.js"

    bindings = [
      # Producer side: this Worker writes to the queue.
      { name = "TELEMETRY_QUEUE", type = "queue", queue_key = "telemetry" },
      { name = "TELEMETRY_DB", type = "d1", d1_database_key = "telemetry" },
    ]
  }
}
```

- **Producer and consumer are declared in different places.** A producer is a `queue` binding on the Worker that writes; the consumer is declared on the queue, because Cloudflare gives a queue exactly one. A Worker may consume several queues, and any number of Workers may produce to one.
- **Ordering is derived, not declared.** A queue must exist before a Worker can bind it, and the Worker must exist before it can be named as that queue's consumer. The layer resolves the queue from variables alone and the consumer from the deployed Worker's name, so Terraform works out `queue -> Worker -> consumer` from the references without a `depends_on`.
- **D1 schema is not Terraform's.** The layer owns the database and the binding; tables come from migrations. A migration is an ordered one-way change, which is not what a plan reconciling desired state does.

  Migrations live in the layer at `migrations/<database_key>/0001_initial_schema.sql`, keyed by the same logical key a binding uses. After every `workers` apply, [`d1-migrations.sh`](../.github/scripts/d1-migrations.sh) reads the `d1_databases` output, applies whatever has not run yet and records it in a `d1_migrations` table inside each database, so a re-run is a no-op. File names are validated before anything is applied, a directory naming no database fails the run, and a migration that removes data is called out in the log - D1 has no snapshot to restore from. See [migrations/README.md](layers/workers/migrations/README.md).
- **Every D1 field is replace-on-change.** Name, jurisdiction and location are fixed at creation, and a replaced D1 database is an empty one - there is no snapshot and no undo. Read a plan proposing a replacement as a plan to lose the data.

### Architectural Standards
- **External Source Files:** JavaScript and TypeScript Worker source files are stored under `deployment/layers/workers/scripts/` and referenced by relative path. Script source code is not embedded directly in `.tfvars`.
- **Content Hashing:** The module calculates SHA-256 hashes of script files automatically, ensuring that code updates trigger deployment plans.
- **Secrets Store Integration:** Production secrets are bound using Cloudflare Secrets Store references rather than plain-text environment variables, preventing credential exposure in Terraform state.
- **Workers KV Scalability:** `max_managed_pairs` limits the number of KV entries managed directly in Terraform. Large datasets should be synchronised using `wrangler kv bulk put` against the output namespace ID.
- **Data Planes Stay Out Of State:** KV pairs beyond configuration, D1 rows and queue messages are all loaded or produced outside Terraform. The layer owns the container and the binding; the pipeline and the application own the contents.

### Guardrails

| Variable | Default | Effect |
| --- | --- | --- |
| `allow_inline_secret_text` | `false` | Fails the plan if a Worker carries a `secret_text` binding, which holds the literal secret in the variable file, the plan output and state. Use a `secrets_store_secret` binding instead. |
| `allow_unpinned_compatibility_date` | `false` | Fails the plan if a Worker has neither its own `compatibility_date` nor `default_compatibility_date`, which would pin its runtime to whenever it was last uploaded. |
| `allow_disabled_observability` | `false` | Fails the plan if a Worker is deployed with Workers Logs off. Sample with `head_sampling_rate` where the concern is volume. |
| `allow_queues_without_consumer` | `false` | Fails the plan if a queue has nothing reading it. Producers keep succeeding while the backlog ages out at the retention period, with nothing raising an error. A queue another queue dead letters into is exempt. |
| `allow_queue_consumer_without_dead_letter_queue` | `false` | Fails the plan if a consumer has no dead letter queue, in which case a message that fails `max_retries` times is deleted with no copy to examine. |
| `allow_replicated_d1_in_jurisdiction` | `false` | Fails the plan if a database restricted to a `jurisdiction` also has read replication on, which keeps a copy of the data in every supported region. |

---

## Load Balancing

The `load_balancing` layer manages origin health monitors, origin pools, and zone-level load balancers.

```hcl
# accounts/account_a/load_balancing.tfvars
load_balancers = {
  api_lb = {
    zone_key     = "primary"
    lb_hostname  = "api.example.com"
    proxied      = true
    steering_policy = "dynamic_latency"

    origins = [
      { name = "origin-primary", address = "203.0.113.10", weight = 1.0 },
      { name = "origin-secondary", address = "198.51.100.20", weight = 1.0 },
    ]

    health_check = {
      type           = "https"
      path           = "/healthz"
      interval       = 60
      timeout        = 5
      retries        = 2
      expected_codes = "2xx"
    }
  }
}
```

Monitors and origin pools operate at account scope, whilst the load balancer hostname binding is scoped to the target zone. Hostnames must reside within the apex domain of the referenced `zone_key`.

---

## Authenticated Origin Pulls

Authenticated Origin Pulls (AOP) is mutual TLS between the Cloudflare edge and the origin. The edge presents a client certificate on the origin connection, and an origin configured to verify it stops serving anything that did not arrive through Cloudflare - closing the hole that a WAF rule cannot, where an attacker who has learned the origin IP address connects to it directly and bypasses every edge control.

Managed by the `origin_pulls` layer, which calls [`modules/authenticated_origin_pulls`](../modules/authenticated_origin_pulls/) once per zone. It is split from `zones` for two reasons. Its state holds private keys, and putting them in the state that also owns every zone would make the most sensitive state in the repository the one most people need to plan against. And its token needs `SSL and Certificates:Edit` but must hold neither `Zone:Edit` nor `DNS:Edit` - an identity the origin trusts, combined with the ability to repoint a hostname, is a materially bigger prize than either alone.

### Two scopes

| Scope | Resource | What it covers |
|---|---|---|
| Zone-level | `cloudflare_authenticated_origin_pulls_settings`, `cloudflare_authenticated_origin_pulls_certificate` | Every hostname in the zone, on one certificate |
| Per-hostname | `cloudflare_authenticated_origin_pulls`, `cloudflare_authenticated_origin_pulls_hostname_certificate` | One hostname, on a certificate of its own |

Where both cover a hostname, Cloudflare applies the per-hostname association. That is what lets `api.example.com` hold a dedicated certificate its origin alone trusts, while the rest of the zone keeps the zone-level posture.

```hcl
origin_pulls = {
  primary = {
    enabled         = true
    certificate_key = "edge_client" # zone-wide; omit to use Cloudflare's default certificate

    hostnames = [
      { hostname = "api", certificate_key = "api_origin" },
      { hostname = "legacy", certificate_key = "api_origin", enabled = false },
      { hostname = "partner", certificate_id = "2458ce5a-0c35-4c7f-82c7-8e9487d3ff60" },
    ]
  }
}
```

A hostname is qualified against its zone, and one belonging to another zone fails the plan rather than being silently turned into `api.other.com.example.com`. `enabled = false` parks an association without deleting it, which is the reversible way to take a hostname out.

### Cloudflare's default certificate identifies Cloudflare, not you

A zone that turns AOP on without uploading a certificate runs on the certificate the Cloudflare edge presents for **every** customer on the platform. An origin that trusts it therefore accepts anything proxied through any Cloudflare account, not only this one.

That is still a real filter in front of an origin that would otherwise accept traffic from anywhere, so it is allowed and a `check` warns on each zone using it. Where the origin is relied on to identify the tenant - a shared origin, a cardholder-data environment - upload a certificate of your own and set `certificate_key`. Setting `allow_shared_cloudflare_certificate = false` turns that warning into a failed plan for the whole account.

### Exporting the trust bundle to the origin

The layer's `origin_trust_bundles` output is the deliverable for whoever configures the origin: per zone, the PEM the origin's client-certificate trust store has to hold. It carries Cloudflare's Origin Pull CA for a zone running on the default certificate, and the uploaded certificates for a zone running on its own. Certificates only - no private key is ever output.

```bash
terraform -chdir=layers/origin_pulls output -json origin_trust_bundles \
  | jq -r '.primary' >cloudflare-client-ca.pem
```

```nginx
# NGINX, and the NGINX ingress controller's server-snippet
ssl_client_certificate /etc/nginx/cloudflare-client-ca.pem;
ssl_verify_client on;
```

For Azure Application Gateway, upload the same file as a Trusted Client Certificate on an SSL profile and attach that profile to the listener. Both verify the chain only; neither checks *which* certificate was presented, so a bundle holding more than one accepts any of them.

### Order of operations

Applying this layer changes what Cloudflare **sends**. It does not make the origin ask for anything, and nothing in this state can see whether the origin has been changed.

1. Apply `origin_pulls`.
2. Take the bundle out of `origin_trust_bundles` and install it at the origin.
3. Switch the origin to require a client certificate.

Doing 3 before 1 fails every request in between. Removing a certificate runs the same sequence backwards: stop requiring it at the origin first.

### Secrets Injection

Certificate material never goes in `.tfvars`. It is supplied at plan time, keyed by certificate, from the `<account>-plan` environment's `TF_VAR_ORIGIN_PULL_CERTIFICATES`:

```bash
export TF_VAR_origin_pull_certificates="$(jq -n \
  --rawfile cert api.crt --rawfile key api.key \
  '{api_origin: {certificate: $cert, private_key: $key}}')"
```

PEM is line-structured and a value flattened to one line is rejected by Cloudflare, which is why the keys are read with `--rawfile` rather than pasted. The plan fails for a `certificate_key` naming material that was not supplied, and for supplied material nothing refers to - an unused private key in state is one nobody rotates and nobody misses.

Self-signed is normal here: the origin is told to trust this certificate itself, so there is nothing for a public CA to add. Cloudflare does not renew an uploaded certificate, and an expired one fails every origin connection it covers, so watch `expires_on` in the `certificates` output.

### Governing defaults

| Setting | Default | Effect |
|---|---|---|
| `default_zone_level_enabled` | `false` | Zone-level AOP is opt-in per zone rather than inherited. |
| `allow_shared_cloudflare_certificate` | `true` | Permits a zone to run on Cloudflare's default certificate, with a `check` warning per zone. `false` fails the plan instead. |
| `cloudflare_origin_pull_ca_certificate` | `null` | Uses the copy vendored at `layers/origin_pulls/ca/`. See that directory's README to refresh it. |

### Out of Scope

Edge mTLS in the other direction - client certificates presented *by visitors to Cloudflare*, through API Shield or an Access mTLS policy - is a different resource family (`cloudflare_mtls_certificate`, `cloudflare_zero_trust_access_mtls_certificate`) and is not managed here. The zone's SSL mode, which has to be `full` or `strict` for any of this to apply, belongs to the `zones` layer.

---

## Turnstile

The `turnstile` layer manages Cloudflare Turnstile widgets: the CAPTCHA replacement a form embeds, and the secret its backend validates the resulting token with. A widget is account-scoped and attached to no zone - the hostname list is free text, so a widget may legitimately name a domain this account does not hold, and Cloudflare will not warn when a hostname is wrong. The widget simply refuses to render on the page that embeds it.

```hcl
# accounts/account_a/turnstile.tfvars
turnstile_widgets = {
  primary = {
    name = "Primary site (example.com)"
    domains = [
      "example.com",
    ]
    mode = "managed"
  }
}
```

A hostname covers itself and every subdomain, so `example.com` also serves `www.example.com` - and listing `www.example.com` does *not* serve the apex.

### The sitekey is the handover, and Terraform cannot complete it

A widget is two keys. The sitekey is public and belongs in the page; the secret is sent by the backend to `/siteverify`. This layer creates the widget and holds both, but it does not manage the page or the backend, so nothing here can tell whether a widget protects anything at all. Read `turnstile_sitekeys` after an apply and hand each value to whoever owns the page.

That asymmetry is also why a replacement is an outage rather than a diff. Updating a widget in place - hostnames, mode, branding - keeps the sitekey and live pages keep working. Replacing one issues a *new* sitekey while every page still carries the old one, and every challenge fails until those pages are redeployed. A `region` change, a key rename and an apply against an empty state all replace. Read any plan on this layer for "must be replaced" before approving it.

### Adopting widgets that already exist

If widgets are already in the account - and for Turnstile they usually are, because a widget is created in the dashboard the moment somebody protects a form - adopt them rather than letting this layer create duplicates. `layers/turnstile/imports.tf` carries the dashboard query and a commented `import` block; the import id is `<account_id>/<sitekey>`. See that file before the first apply.

### Secrets

Nothing is injected into this layer: Cloudflare issues the secret, and Terraform records what the API returned, so **this layer's state holds every widget's secret key in plain text**. Anyone holding it can forge a passing `/siteverify` response for any form the widget protects, and it cannot be rotated in place - a new secret means a new widget, and a new widget means a new sitekey. The secret is deliberately not re-exported as a root output; read one from state when handing it over. Treat a leak of this state, or of a saved plan of this layer, as a compromise of every protected form.

### Governing defaults

| Setting | Default | Effect |
|---|---|---|
| `default_widget_mode` | `"managed"` | Cloudflare decides, and asks for a click only when it needs one. The mode that fails visibly. |
| `default_widget_region` | `"world"` | `"china"` is a separate widget network and is fixed at creation, so it is never a silent default. |
| `max_domains_per_widget` | `200` | Cloudflare's Enterprise ceiling, enforced before the API sees the widget (10 on every other plan). |
| `allow_offlabel_widgets` | `false` | Removing Cloudflare branding is a contractual and design decision, so it takes a pull request that says why. |
| `invisible_mode_privacy_addendum_accepted` | `false` | Invisible mode tells the visitor nothing, which is why Cloudflare requires its privacy addendum first. |

### Out of Scope

Embedding the sitekey, calling `/siteverify`, and storing the secret in the backend all happen outside this repository. Pre-clearance interacts with the WAF challenge that the issued `cf_clearance` cookie satisfies, but the rule itself belongs to the `waf` layer.

---

## Pages

The `pages` layer manages Cloudflare Pages projects - static and Jamstack front ends - through [`modules/pages_project`](../modules/pages_project/), once per project. It declares the project, its Git source and branch deployment rules, its per-environment bindings and env vars, and its custom domains, including the proxied CNAME behind each. It is its own layer rather than part of `workers`: Pages has its own permission group, and the token that can change what a site serves should not also be able to rewrite the Workers in front of the API that site calls.

```hcl
# accounts/account_a/pages.tfvars
pages_projects = {
  docs_site = {
    name = "account-a-docs"
    source = {
      type      = "github"
      owner     = "example-org"
      repo_name = "docs"
    }
    build          = { build_command = "npm run build", destination_dir = "dist" }
    custom_domains = [{ hostname = "docs.example.com", zone_key = "primary" }]
  }

  admin_portal = {
    name              = "account-a-admin"   # Direct Upload: no `source`
    access_protection = "all"
    production        = { secret_names = ["SESSION_SECRET"] }
    custom_domains    = [{ hostname = "admin.example.com", zone_key = "primary" }]
  }
}
```

A project with a `source` builds on Cloudflare from GitHub or GitLab. Cloudflare's Git app must already be installed on the owner with access to the repository, and Terraform cannot install it. A project without one is **Direct Upload**: this layer creates it, and deployments arrive from `wrangler pages deploy` in the application's own pipeline. Either way, **this layer does not deploy anything**. A newly created project serves nothing until its first deployment lands.

### Custom domains need a DNS record, and the API does not create it

Adding a custom domain through the API - unlike the dashboard - does not write its DNS record, so the domain sits at `pending` and no certificate is issued. Give each custom domain a `zone_key` and this layer writes a proxied CNAME to the project's real pages.dev hostname. Without one, the plan fails unless `allow_unmanaged_pages_hostnames` is set, for a record genuinely managed elsewhere. A custom domain must not also be a record in `dns.tfvars`.

### Access: the pages.dev hostname is the bypass

Protecting an internal portal is a `zerotrust` change, made with that layer's token. This layer has no Zero Trust scope, so it cannot write or check an Access application. What it does is work out which hostnames one has to cover, and publish them in the `pages_access_applications` output, shaped as `access_applications` entries for `zerotrust.tfvars`. Copy each entry under the same key and add `policy_keys`.

That list is the reason the output exists. Every project also answers on `<subdomain>.pages.dev` and every preview on `*.<subdomain>.pages.dev`, and neither is covered by an Access application on the custom domain. The wildcard does not match the bare hostname either. So:

| `access_protection` | Hostnames in the hand-over | Use for |
|---|---|---|
| `previews` (default) | `*.<subdomain>.pages.dev` | A public site whose unreleased branches should not be |
| `all` | every custom domain, `<subdomain>.pages.dev`, `*.<subdomain>.pages.dev` | An internal admin portal or dashboard |
| `none` | nothing | Only with `allow_unprotected_previews`, or previews switched off |

The subdomain is read from the project after apply, not built from its name. pages.dev is one namespace across every Cloudflare account, and a name somebody else already holds is given a random suffix. Re-read the output after any apply that changes a project's custom domains: the `zerotrust` entry is a copy, and a hostname added here and not there is served without a login.

### Secrets and the browser

Plain `env_vars` are readable in the dashboard, the API and every plan of this layer. A secret is listed by name under `secret_names` and its value arrives in `TF_VAR_PAGES_PROJECT_SECRETS` in the `<account>-plan` environment - see [VARIABLES_AND_SECRETS.md](../VARIABLES_AND_SECRETS.md). The plan fails for a declared secret with no value, or a value no project declares.

Both kinds of variable reach the build as well as Functions. A framework that inlines variables with a public prefix (`VITE_`, `NEXT_PUBLIC_`, `PUBLIC_`, `REACT_APP_` and similar) writes the value into the JavaScript every visitor downloads, whatever type it was stored as. The plan refuses a secret under such a name outright, and refuses a plain variable whose name looks like a credential unless `allow_credential_like_plain_env_vars` is set.

**This layer's state holds every secret value in plain text.** Cloudflare never returns a secret once set, but Terraform records what it sent.

`production` and `preview` are configured separately and preview inherits nothing. A preview is built from any branch, so it should not be handed production's bindings or secrets by default.

### Adopting projects that already exist

A project name is unique per account, so applying against a project created in the dashboard fails rather than duplicating it. `layers/pages/imports.tf` carries the API query and commented `import` blocks for projects (`<account_id>/<project_name>`) and domains (`<account_id>/<project_name>/<hostname>`). A project with secret env vars cannot be imported; remove the secrets, import, then let this layer set them again.

### Governing defaults

| Setting | Default | Effect |
|---|---|---|
| `default_production_branch` | `"main"` | For a project that does not state one. |
| `default_preview_deployment_setting` | `"all"` | Every pushed branch gets a preview - which is why the next default matters. |
| `default_access_protection` | `"previews"` | Previews are listed in the Access hand-over unless a project says otherwise. |
| `allow_unprotected_previews` | `false` | A project publishing previews with `access_protection = "none"` fails the plan. |
| `allow_unmanaged_pages_hostnames` | `false` | A custom domain with no `zone_key` fails the plan, because nothing would create its record. |
| `allow_credential_like_plain_env_vars` | `false` | A plain env var named like `*_TOKEN`, `*_SECRET` or `API_KEY` fails the plan. |

### Known gaps

- The API may return defaults for `deployment_configs` fields this layer leaves unset, which shows as drift on the plan after the first apply. Pin the field in `pages.tfvars` if it does.
- Unicode (IDN) custom domains are rejected; punycode is accepted. The Pages API has not been confirmed to normalise them the way the zones API does.
- `web_analytics_token`, Durable Object, Hyperdrive, AI, Vectorize and mTLS bindings are not exposed yet.

---

## Adding a new account

In enterprise and MSP environments, onboarding an account or tenant should follow isolated per-customer repository patterns rather than co-locating multiple clients in a single repository.

Managing multiple customers under one repository shares pipeline permissions, GitHub Environments, and R2 state access, exposing every tenant to a single operator mistake.

To automate repository provisioning and downstream code delivery, use the [Cloudflare Landing Zone Release Manager](https://github.com/itsharryshelton/CloudflareLandingZone-Release-Manager):

```powershell
# Execute the Release Manager to provision an isolated deployment repository and versioned modules
.\Invoke-CloudflareLandingZoneRelease.ps1 `
    -TargetOwner "Org-Name" `
    -Prefix "cflz" `
    -DeploymentRepoName "{prefix}-deployment" `
    -ModuleRepoPattern "terraform-cloudflare-lz-{module}" `
    -UseUpstreamSource `
    -Visibility "private"
```

The Release Manager automates:
1. Creating dedicated private GitHub repositories under the target customer or organisation estate.
2. Publishing the deployment orchestrator (`cflz-deployment`) and individual versioned modules (`terraform-cloudflare-lz-<module>`).
3. Seeding the initial account configuration tree (`accounts/**`) whilst ensuring operator edits are preserved and never overwritten on future upstream releases.

### Onboarding Accounts within a Deployment Repository

Within your customer's dedicated deployment repository, you can manage multiple administrative accounts (for example: `production`, `staging`, `development`):

1. Create a directory `accounts/<account_name>/`.
2. Copy all twenty-two template `.tfvars` files from `accounts/account_a/`:
   - `account.tfvars`
   - `account_governance.tfvars`
   - `bulk_redirects.tfvars`
   - `device_posture.tfvars`
   - `dns.tfvars`
   - `gateway.tfvars`
   - `lists.tfvars`
   - `load_balancing.tfvars`
   - `logpush.tfvars`
   - `origin_pulls.tfvars`
   - `pages.tfvars`
   - `r2.tfvars`
   - `rules.tfvars`
   - `tags.tfvars`
   - `tunnels.tfvars`
   - `turnstile.tfvars`
   - `waf.tfvars`
   - `wan.tfvars`
   - `workers.tfvars`
   - `zerotrust.tfvars`
   - `zone_config.tfvars`
   - `zones.tfvars`
3. Update `account.tfvars` with the target Cloudflare Account ID.
4. Populate `zones.tfvars` with your zone inventory, and configure layer-specific `.tfvars` files as required.
5. Create the account's `<account>-plan` environment by hand, re-run `.github/scripts/bootstrap-environments.sh` for its `<account>-<layer>-apply` environments and `<account>-tags-apply`, and give each its own scoped `CLOUDFLARE_API_TOKEN`. The R2 state credentials are repository secrets, shared by every account. See [VARIABLES_AND_SECRETS.md](../VARIABLES_AND_SECRETS.md).
6. The CI/CD pipeline dynamically discovers the new account tree and includes it in subsequent plan and apply runs.

No `.tf` orchestrator modifications are required.

## Adding a new product layer

To introduce a new Cloudflare product layer:

1. Create a directory `layers/<product>/`, named after the Cloudflare product it manages.
2. Add the standard root files: `terraform.tf`, `providers.tf` (documenting the minimum required token permissions), `variables.tf`, `locals.tf`, `<subject>.tf`, and `outputs.tf`.
3. If the layer binds to zones, include `zone_lookup.tf` and define `referenced_zones` so it resolves zone keys dynamically via `data "cloudflare_zone"` instead of reading external state files.
4. Add `preflight.tf` to assert on all logical key references and platform guardrails at plan time.
5. Provide a baseline `defaults.auto.tfvars` where appropriate.
6. Add `<product>.tfvars` to each account directory under `accounts/*/`.
7. Leave `.github/scripts/tf-matrix.sh` alone. A layer's tier is derived from its own source: a `data "cloudflare_zone"` block puts it in tier 3, anything else in tier 2. Only where that is wrong - the layer must apply ahead of everything, or must wait for zones without ever reading one - add a `tier.tf` to the layer declaring `locals { apply_tier = <1|2|3> }`, with a comment saying why the source cannot express it. The declaration wins over the derivation, and is range-checked and cross-checked against the `zone_base` call at selection time.
8. Add the layer to the `ci.yml` self-test: the per-layer loop, the `zones.tfvars` expectation if it declares `zones`, the tier 3 expectation if it resolves a zone, and the `tags.tfvars` expectation if it declares `resource_tags`.
9. Create a `<account>-<product>-apply` environment per account with its own scoped token (`ONLY_LAYER=<product>` with `bootstrap-environments.sh`). If the layer takes a `TF_VAR_` secret, add a conditional export to the plan step of `_terraform-run.yml`.
