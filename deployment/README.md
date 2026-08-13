# `deployment` - the deployment template

Everything you edit lives here. The modules under [../modules/](../modules/) stay agnostic: flat arguments, real IDs, one resource group each, no knowledge of accounts, keys or profiles. You should avoid editing ".tf" files, as this is designed to be an upstream/downstream method. E.g. You have your sample Repo; this is then copied to a target account Repo, where you then make edits to the .tfvars files to match the target accounts; changes to .tf or modules should happen in the upstream repo, then propagated to downstream repos.

## Directory Structure

```deployment/
├── layers/                            # code, shared by every account
│   ├── zones/                         # own state: zones, settings, DNS
│   ├── waf/                           # own state: firewall + rate limiting
│   ├── load_balancing/                # own state: monitors, pools, LBs
│   ├── r2/                            # own state: buckets, CORS, lifecycle, domains
│   ├── account_governance/            # own state: members, user groups
│   ├── zerotrust/                     # own state: Access, policies, tokens, IdPs
│   ├── gateway/                       # own state: SWG DNS, network and HTTP policies
│   └── wan/                           # own state: WAN tunnels, static routes
└── accounts/                          # config, one tree per Cloudflare account
    ├── account_a/
    │   ├── account.tfvars             # account id       -> every layer
    │   ├── zones.tfvars               # zone inventory   -> zones, waf, load_balancing, r2
    │   ├── dns.tfvars                 # zone config      -> zones
    │   ├── waf.tfvars                 # policies         -> waf
    │   ├── load_balancing.tfvars      # load balancers   -> load_balancing
    │   ├── r2.tfvars                  # object storage   -> r2
    │   ├── account_governance.tfvars  # dashboard access -> account_governance
    │   ├── zerotrust.tfvars           # Access           -> zerotrust
    │   ├── gateway.tfvars             # egress filtering -> gateway
    │   └── wan.tfvars                 # site tunnels     -> wan
    └── account_b/
        └── ...
```

Each layer is a root module with its own state, holding `terraform.tf`, `providers.tf`, `variables.tf`, `locals*.tf`, one `<subject>.tf`, `preflight.tf`, `outputs.tf` and its own `defaults.auto.tfvars`.

Layers are named after the Cloudflare product they manage, with no ordering prefix. There is only one real dependency and it is not a chain:

```
zones ──┬── waf
        ├── load_balancing        (waf, load_balancing and r2 are independent)
        └── r2                    (only when a bucket has a custom domain)

account_governance                (no zone involved, so no dependency at all)
zerotrust                         (same, but see below)
gateway                           (same; it filters egress, which no zone owns)
wan                               (same, and no zone anywhere in the layer)
```

`waf`, `load_balancing` and `r2` have no relationship to each other, so numbering them would assert a sequence that does not exist. `account_governance` touches no zone, so it neither creates nor resolves one and can apply whenever. `zerotrust` holds no zone in its state either, but an Access application only ever sees a request if the DNS record for its hostname exists and is proxied - so `zones` in practice comes first, and the failure if it does not is a login page nobody can reach rather than a Terraform error. `r2` only reaches for a zone when a bucket is served from a custom domain; a deployment of private buckets looks nothing up. Ordering is enforced where it can actually be enforced - pipeline stage dependencies, and the fact that the dependent layers resolve a zone by name and fail if it is absent - not by a filename that merely hints at it.

## Why split this way

**Account > separate layer run.** One `provider "cloudflare"` block carries one API token, and Terraform cannot pass a dynamic provider alias to a `for_each`'d module. So accounts cannot be `for_each` keys - each account is its own run, with its own token and its own state key. That is also the isolation you want: a token compromised for one customer cannot reach another.

**Product > separate state.**  A WAF or load balancer apply cannot propose destroying a zone, because zones are not in its state. Zone deletion is the worst blast radius in Cloudflare — it takes every DNS record with it. It also lets each layer's pipeline identity hold a narrower token: waf needs `Zone WAF:Edit` + `Zone:Read`, never `Zone:Edit`. The split cuts the other way too: `account_governance` is the only layer whose token can hand somebody else access to the Cloudflare account, and `zerotrust` the only one whose token can hand somebody access to what sits behind Access. Neither holds anything at zone scope in exchange.

**Zone > a `for_each` key, not a directory.** A directory per account×zone would
mean adding a zone requires adding `.tf` code, duplicated N×M, and a fleet-wide
version bump would touch N×M module sources. Adding a zone here is two edits to
`zones.tfvars` and `dns.tfvars`.

## Layers do not read each other's state

The waf, load_balancing and r2 layers resolve a zone key to a zone ID with `data "cloudflare_zone"` filtered by name, not `terraform_remote_state`. The states stay independent - any of them can be applied, re-inited or relocated without the others noticing.

The cost is real and worth knowing: those layers call the Cloudflare API at plan time, so they cannot be planned offline, and they fail if the zone does not exist yet. Apply `zones` first; `waf`, `load_balancing` and `r2` can then run in any order, or concurrently. `account_governance` reads the API too - it resolves role and permission group names to IDs - and so does `zerotrust`, which reads the account's existing Zero Trust organization so it can adopt the team name rather than demand one, and `gateway`, which resolves Cloudflare's content category, security category and application catalogues so that an account tree can say `"Microsoft 365"` instead of `606`. None of them waits on another layer. **`zones` and `wan` are the two layers that can be planned with no credentials at all**: `wan` is account-scoped, resolves nothing by name and holds no data source, so CI plans it against every account on every push.

## Config precedence

1. `layers/<layer>/defaults.auto.tfvars` - platform baseline, auto-loaded from the layer's working directory. Customer-agnostic.
2. `accounts/<account>/*.tfvars` - passed with `-var-file`, so it wins.
3. `local.auto.tfvars` in a layer directory - an operator's local experiment. Gitignored.

`-var-file` does **not** merge: two files both defining `zones` means the last one wins wholesale. That is why the account config is split by *variable* rather than by zone - `zones.tfvars` owns the inventory, `waf.tfvars` owns the policies, and no two files define the same variable.

## What is committed

Layer defaults are customer-agnostic. The account trees **do** carry account IDs and real domains: that is configuration, not secrets, and this repository is private with RBAC.

Never committed, in any file:

```bash
export CLOUDFLARE_API_TOKEN="<per-account, per-layer scoped token>"
export AWS_ACCESS_KEY_ID="<R2 access key>"       # state backend
export AWS_SECRET_ACCESS_KEY="<R2 secret key>"   # state backend
```

`.gitignore` is default-deny for `*.tfvars` with explicit exceptions for `layers/*/defaults.auto.tfvars` and `accounts/*/*.tfvars`, and re-denies `**/terraform.tfvars`, `**/local.auto.tfvars` and `**/*.local.tfvars` after the exceptions so no negation can reach them.

## Running a layer

```bash
cd deployment/layers/zones

# Offline validate - no credentials, no API calls.
terraform init -backend=false
terraform validate

# Plan one account.
export CLOUDFLARE_API_TOKEN="<scoped token>"
terraform plan \
  -var-file=../../accounts/account_a/account.tfvars \
  -var-file=../../accounts/account_a/zones.tfvars \
  -var-file=../../accounts/account_a/dns.tfvars
```

`waf` takes `account.tfvars`, `zones.tfvars`, `waf.tfvars`. `load_balancing` takes `account.tfvars`, `zones.tfvars`, `load_balancing.tfvars`. `r2` takes `account.tfvars`, `zones.tfvars`, `r2.tfvars`. `account_governance` takes `account.tfvars` and `account_governance.tfvars`, and no zone inventory at all. `zerotrust` takes `account.tfvars` and `zerotrust.tfvars`, plus `TF_VAR_identity_provider_secrets` in the environment for any identity provider that authenticates against an OAuth application. `gateway` takes `account.tfvars` and `gateway.tfvars`, and no zone inventory - egress filtering belongs to the account rather than to any one domain. `wan` takes `account.tfvars` and `wan.tfvars`, and no zone inventory either, plus `TF_VAR_wan_ipsec_tunnel_psks` in the environment for any IPsec tunnel whose pre-shared key you choose rather than letting Cloudflare generate.

### Remote state

State lives in Cloudflare R2 through the S3-compatible backend ([docs](https://developers.cloudflare.com/terraform/advanced-topics/remote-backend/)).

The backend block is committed **commented out** so CI can `init -backend=false`; uncomment it per deployment. One key per account per layer:

```bash
terraform init -reconfigure \
  -backend-config="bucket=<state-bucket>" \
  -backend-config="key=account_a/zones.tfstate" \
  -backend-config="endpoints={s3=\"https://<state-account-id>.r2.cloudflarestorage.com\"}"
```

**Locking.** R2 has no DynamoDB equivalent, so two concurrent applies against one
key can corrupt state. `use_lockfile = true` locks with S3 conditional writes,
which R2 supports, and that is set in the backend block.

It needs Terraform 1.11 or newer, so every layer declares
`required_version = ">= 1.11.0"`. The constraint is the point: on an older
Terraform the argument is not recognised and you get an unlocked apply rather than
an error, so the floor has to refuse the run instead. The pipeline pins 1.14.6,
which covers CI, and the constraint covers anyone running locally.

The modules under [../modules/](../modules/) deliberately keep a `>= 1.5.0` floor.
They own no backend, so they stay usable from a root module on an older Terraform.

Concurrency groups in the pipeline serialise runs per state key as a second line
of defence. See [.github/workflows/_terraform-run.yml](../.github/workflows/_terraform-run.yml).

## Referring to other resources

Resources reference each other by **logical key**, never by ID. A WAF policy says `zone_key = "primary"`; the layer resolves that to a zone ID. Keys are permanent identity - renaming one destroys and recreates the resource.

Keys are scoped to their account, so `account_a`'s `primary` and `account_b`'s `primary` are unrelated.

`preflight.tf` in each layer catches what neither variable validation nor a module block can: a `zone_key` pointing at nothing, a `zone_config` key with no matching zone, two WAF policies fighting over one zone, a load balancer hostname outside its zone's domain, an R2 bucket asking to be served anonymously, a Cloudflare WAN static route pointing at a tunnel nothing declares, and a user group naming a member who was never declared. All fail the plan with the offender named.

## WAF Baseline

Ops pick rules by name rather than writing wirefilter expressions:

```hcl
waf_policies = {
  primary = {
    zone_key              = "primary"
    baseline_custom_rules = ["block_admin_from_untrusted", "block_known_exploit_paths"]
    baseline_rate_limits  = ["auth_brute_force", "api_general"]
  }
}
```

The catalogue is in `layers/waf/locals.waf.tf`, parameterised by `waf_trusted_ip_ranges`, `waf_admin_paths` and `waf_blocked_countries` so it serves every customer unchanged.

### Custom rules

| Name | Action | Requires |
|------|--------|----------|
| `block_admin_from_untrusted` | block | `waf_trusted_ip_ranges` |
| `geoblock_countries` | block | `waf_blocked_countries` |
| `block_known_exploit_paths` | block | — |
| `challenge_undisclosed_bots` | managed_challenge | `waf_trusted_ip_ranges` |
| `log_trusted_admin_access` | log | `waf_trusted_ip_ranges` |

### Rate limits

| Name | Mitigation | Notes |
|------|-----------|-------|
| `auth_brute_force` | block | 20 req/min per IP on login and auth paths. |
| `api_general` | managed_challenge | 600 req/min per IP under `/api/`. |
| `origin_error_shield` | block | Counts only origin 5xx responses. |
| `observe_only` | log | Measure before enforcing. Forces `mitigation_timeout = 0`. |

**Baseline rules evaluate before tenant rules.** Cloudflare walks a ruleset in list order and the layer concatenates baseline first, so a tenant rule cannot pre-empt a platform block.

**A rule whose input is empty fails the plan.** This is a safety property: `block_admin_from_untrusted` with an empty `waf_trusted_ip_ranges` renders as "block admin access from everywhere, including you", and `geoblock_countries` with no countries produces `ip.geoip.country in {}`, which Cloudflare rejects.

## Account Governance

Who can sign in to the account, and what they can do once they are in. This is the
layer that hands out access, so read its plans the way you read a firewall diff: a
destroy here revokes a real person's access the moment it applies, and changing an
`email` is a revoke plus a fresh invitation rather than a rename.

Ops name roles and permissions rather than pasting IDs:

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

Role, permission group and resource group IDs are per-account, undocumented
anywhere an operator would look, and grow as Cloudflare ships products. The layer
resolves the names against the account at plan time (`permission_lookup.tf`), and
an unrecognised name fails the plan listing what the account actually has.

Three defaults in `layers/account_governance/defaults.auto.tfvars` do the
governing:

| Setting | Default | Effect |
|---|---|---|
| `default_role_names` | `["Minimal Account Access"]` | A member naming no role gets only the ability to sign in. Everything else arrives through a user group, named once and reviewable in one place. |
| `restricted_role_names` | `["Super Administrator - All Privileges"]` | The plan fails if that role is requested, by name **or** by ID. Granting it is a deliberate edit to this list on its own pull request. |
| `allowed_email_domains` | `[]` (any) | Set it to your own domains and a mistyped or unexpected external address becomes a failed plan rather than an invitation nobody notices. |

Two things this layer deliberately does not do. It does not manage API tokens: a
token is a credential, credentials never enter Terraform state, and this layer's
state is already sensitive enough - it holds the email address, membership ID and
exact permissions of everyone with access. And it does not manage the account
resource itself, so no apply here can propose destroying the account.

A member with `member_ids` rather than a `member_key` is somebody deliberately
managed outside Terraform. The layer will not revoke them, which is the escape
hatch for adopting this on an account that already has people in it.

Scoping a policy to less than the whole account needs a resource group, and the
Cloudflare provider has no resource for creating one. Name an existing group with
`resource_group_names`; leave it empty and the policy covers the account.

## R2

Object storage: the buckets, their CORS and lifecycle policy, their retention
rules, and the hostnames they are served from.

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

### A custom domain's DNS record is not yours to declare

Attaching a custom domain makes Cloudflare create the DNS record itself, in the
zone, pointing the hostname at the bucket. That record is owned by R2 and is not
editable in the dashboard.

The `zones` layer will not touch it. `cloudflare_dns_record` is declared with a
`for_each` over the records in `dns.tfvars`, so Terraform holds one resource per
record it created and nothing else - there is no data source enumerating the
zone and no prune. A record it did not make is invisible to it, and an apply
cannot propose destroying it. You do not need to add it to dns.tfvars!

### The AWS provider is no longer needed for this

Cloudflare's Terraform examples still say the provider "can only manage buckets"
and point at the AWS provider for
[CORS and object lifecycles](https://developers.cloudflare.com/r2/examples/terraform-aws/).
That page is written against provider v4. Since 5.x the Cloudflare provider owns
all of it natively - `cloudflare_r2_bucket_cors`, `_lifecycle`, `_lock`,
`r2_custom_domain` and `r2_managed_domain` - and this layer uses those.

The distinction matters because the AWS route needs an R2 **access key**: an S3
credential with read and write over the objects themselves. Adding one to every
pipeline environment to configure CORS would put data-plane access in a place
that only needs control-plane access. This layer's token cannot read or delete a
single object.

The AWS provider is still the answer for uploading objects (`aws_s3_object`),
which is deliberately out of scope here - a landing zone provisions the bucket,
the application owns what is in it.

### Three settings cannot be deleted, only overwritten

Cloudflare's API has no delete for a bucket's lifecycle policy, its lock rules or
its r2.dev setting, and the provider warns as much at plan time. A resource that
simply disappeared from the graph would leave its last-applied policy live in R2
while Terraform reported it gone, so the module declares all three
unconditionally and expresses "none" as an empty rule list. Emptying
`lifecycle_rules` therefore genuinely clears the policy. CORS does support
delete, so it is created only when there are rules.

The same reasoning is why the r2.dev public URL is declared for every bucket
rather than only the public ones: it is the single toggle that turns a private
bucket into an anonymously readable one, it is two clicks away in the dashboard,
and a plan that said "no changes" while it was on would be wrong.

### Governing defaults

| Setting | Default | Effect |
|---|---|---|
| `allow_public_r2_dev_domains` | `false` | A bucket asking for its `pub-<hash>.r2.dev` URL fails the plan. That URL serves every object to anyone, unauthenticated and uncached, and Cloudflare positions it as a development convenience. Serve objects publicly through `custom_domains`, where the hostname sits in a zone you own and inherits its cache, WAF and TLS posture. |
| `allow_wildcard_cors_origins` | `false` | `allowed_origins = ["*"]` fails the plan. A wildcard lets any page a visitor opens read the bucket from their browser, using their network position. |
| `allow_bucket_wide_object_expiry` | `false` | A lifecycle rule that deletes objects with an empty prefix fails the plan. An empty prefix means the whole bucket, R2 has no versioning, and it is usually a typo in `prefix`. Aborting incomplete multipart uploads is unaffected. |
| `default_bucket_location` | `null` | Cloudflare places each bucket near its first write. Set it (`"weur"`) to land the fleet in one region. A hint, honoured only at creation. |
| `default_jurisdiction` | `null` | Set it (`"eu"`) where residency is a regulatory requirement. Unlike location it is a guarantee - and it is fixed, so moving an existing bucket means recreating it with its objects. |
| `default_storage_class` | `"Standard"` | InfrequentAccess is cheaper to store and dearer to read, with a minimum billable duration, so a fast-turnover bucket costs more in it. Move ageing objects across with a lifecycle rule. |
| `default_custom_domain_min_tls` | `"1.2"` | Cloudflare's own default is 1.0. |

### What this layer does not hold

No R2 access keys. A key is a credential, credentials never enter Terraform
state, and an S3 key with object write is a data-loss tool rather than an
infrastructure one.

And not the Terraform state bucket. Every layer in this repository keeps its
state in R2, and a layer that managed the bucket its own state lives in could
propose destroying it - a plan that cannot be applied safely in either order.
Create the state bucket out of band, once, and leave it out of `r2_buckets`.

### One thing to know before you rely on a lock rule

An object under an active lock rule cannot be deleted or overwritten by anybody
until its retention expires: not the application, not an operator with full R2
credentials, and not this pipeline. That is the point of it and also the risk -
a rule is far easier to add than to live with, and `retain_indefinitely` means
the objects, and the bucket holding them, can never be removed.

The module fails the plan where a lifecycle deletion overlaps a lock rule's
prefix. R2 accepts that combination and then refuses the deletion object by
object, so the storage is paid for indefinitely and nothing reports why.

## Zero Trust

Cloudflare Access: the team name the account logs in under, the identity
providers it offers, the audiences it recognises, the policies it evaluates and
the applications behind them. Read a plan from this layer the way you read the
account governance one - it decides who reaches internal systems, and a destroy
here closes a door somebody is standing at.

Ops name things by key, and the layer resolves the keys:

```hcl
access_groups = {
  platform_engineers = {
    name = "Platform Engineers"
    include = {
      entra_groups = [
        { identity_provider_key = "entra_id", group_id = "<entra group object id>" },
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

`policy_keys` is ordered. Cloudflare evaluates an application's policies in the
order they are listed and the first match decides, so a `deny` belongs at the
front.

### The team name is not created here

The account needs a Zero Trust organization before this layer can do anything,
and Terraform cannot create one. The Cloudflare provider's
`cloudflare_zero_trust_organization` resource issues an HTTP `PUT`, so it adopts
and manages an organization that exists and gets `organization_not_found` on an
account that has never enabled Zero Trust. The resource also has no
`terraform import`.

So the team name is chosen once, out of band:

```bash
curl -X POST "https://api.cloudflare.com/client/v4/accounts/<account_id>/access/organizations" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"name":"Acme Internal Applications","auth_domain":"acme.cloudflareaccess.com"}'
```

or in the dashboard under Zero Trust, then Settings, then Custom Pages, which
prompts for it the first time the section is opened. After that, set
`zero_trust_team_name` and the layer owns it. Leave `zero_trust_team_name` unset
and the layer adopts whatever team name the account already has, which is the
right answer when taking over an account somebody configured by hand.

Changing the team name later renames the team domain: every Access application
URL changes, every enrolled WARP device has to re-enrol, and the old name is
released for anybody else to register. The layer refuses unless
`allow_team_name_change` is set.

### Secrets

An identity provider's OAuth client secret - the Entra ID app registration's -
**never goes in a tfvars file**. It reaches Terraform as
`TF_VAR_identity_provider_secrets`, a map keyed the same way as
`identity_providers`, read from the layer's apply environment:

```bash
export TF_VAR_identity_provider_secrets='{"entra_id":"<the secret>"}'
```

Two consequences worth stating plainly. `accounts/*/*.tfvars` is deliberately
un-ignored so account trees can be committed, so a secret written there is
committed by the next `git add`. And the value is in Terraform state in plain
text whatever route it takes, alongside the client secret of every service
token, because Cloudflare shows a generated secret once and Terraform records
what it received. This layer's state is a credential store: keep it in R2 behind
environment-held keys, never commit it, and treat a saved plan file as equally
sensitive. A leak means rotating every service token and every identity provider
secret in it.

Service token client secrets are deliberately not outputs, so they do not end up
in the plan comment on a pull request.

### Governing defaults

| Setting | Default | Effect |
|---|---|---|
| `restricted_policy_decisions` | `["bypass"]` | The plan fails if a policy asks for `bypass`, which removes authentication entirely from every application it is attached to. Allowing it is a deliberate edit here on its own pull request. |
| `allowed_email_domains` | `[]` (any) | Set it and an `include` rule admitting an address or domain from anywhere else fails the plan. `exclude` rules are left alone - excluding an outside address is not the problem. |
| `lock_dashboard_to_read_only` | `false` | Turn it on once the account is steady and the Zero Trust dashboard becomes read-only for everybody, whatever their role, which makes this repository the only route to an Access change. |
| `allow_team_name_change` | `false` | A typo in `zero_trust_team_name` fails the plan instead of renaming the team domain. |
| `default_session_duration` | `"24h"` | How long a session survives before re-authentication, for anything that sets none of its own. |
| `default_service_token_duration` | `"8760h"` | A year. Cloudflare also accepts `"forever"`; a credential nobody is obliged to rotate outlives whoever created it. |
| `user_seat_expiration_inactive_time` | `"730h"` | Cloudflare's minimum. It is what stops a leaver holding a seat indefinitely. |

### Destinations, not self_hosted_domains

An application's hostnames go in `destinations`. Cloudflare deprecated the
top-level `self_hosted_domains` list in provider 5.x - supported only until 21
November 2025 - and `destinations` replaces it, with public hostnames and
private (WARP-reachable) IPs and SNIs in one list.

```hcl
access_applications = {
  grafana = {
    name        = "Grafana"
    domain      = "grafana.example.com"
    policy_keys = ["platform_engineers_mfa"]

    extra_destinations = [
      { uri = "metrics.example.com" },
      { type = "private", cidr = "10.10.0.0/24", l4_protocol = "tcp", port_range = "5432" },
    ]
  }
}
```

The one trap: `destinations` is the **complete** set of what Access secures, not
a list of extras on top of `domain`. Cloudflare's own wording is "if destinations
are provided, then self_hosted_domains will be ignored", and `domain` is only
"the primary hostname ... displayed if the app is visible in the App Launcher".
Send a destinations list that omits the primary hostname and the application
stops being protected on its own domain while the dashboard still shows that
domain against it.

The layer therefore prepends `domain` to the list for you, and the plan refuses
a list that restates it or that names the same destination twice. Every hostname
in the list still needs its own proxied DNS record.

### Two limitations worth knowing before you hit them

`group_keys` cannot be used inside an `access_groups` rule. A group nesting
another group the same layer creates is a Terraform dependency cycle rather than
anything Cloudflare would complain about, and the resulting message would name a
local rather than the configuration. Nest an externally managed group with
`group_ids`, or merge the two rule sets. The plan says so.

`allowed_idp_keys` on an application cannot name an identity provider created in
the same run. Cloudflare models the field as a set, and a set holding an ID that
is only known after apply is unknown in its entirety, which the provider rejects
at plan time. Apply the provider first and the application after, or express the
restriction as `login_method_keys` in a policy - which is enforced rather than
merely displayed, and copes with an ID that is not known yet.

## Gateway (Secure Web Gateway)

Corporate egress filtering: the DNS, network and HTTP policies that decide what
leaves the network, what is inspected on the way out, and what is stopped. Read a
plan from this layer as a change to what people can reach - a new block closes
something somebody is using today, and a new bypass stops a channel being watched.

### Three pipelines, not one list

DNS, network and HTTP are three separate builders. A policy belongs to exactly
one of them, and each is ordered independently.

| Type | Sees | Blind to | Actions |
|---|---|---|---|
| `dns` | The query, before a connection exists | Everything past the hostname. And any client resolving over DNS-over-HTTPS to somebody else's resolver | allow, block, override, safesearch, ytrestricted |
| `network` | The L4 connection: ports, protocols, IPs, the TLS SNI | The payload | allow, block, l4_override |
| `http` | The decrypted request | Anything exempted from inspection | allow, block, off, on, scan, noscan, isolate, noisolate, quarantine, redirect |

DNS filtering is the cheapest place to enforce a block and the easiest to walk
around, which is why the baseline blocks security categories at DNS **and** at
HTTP. The second rule is not redundant: a browser that resolves through a
third-party DoH endpoint never sends Gateway a query, and the HTTP policy sees
the connection anyway.

### Precedence is the whole of the rule ordering

Gateway walks a builder in ascending precedence and stops at the first allow or
block that matches. A rule can be perfectly written and never reached.

Precedence is therefore a required field rather than something derived from the
order of the HCL. A map has no order in Terraform, so deriving it would mean
sorting on the logical key - and renaming a key would silently reorder the
firewall. Leave gaps of 100 so a rule can be inserted later without renumbering
everything after it.

Precedence below `reserved_precedence_ceiling` (100) belongs to the platform
baseline, and an account tree asking for one fails the plan. That is what makes
"platform rules first" a fact rather than a convention.

```hcl
gateway_policies = {
  allow_sanctioned_smtp_relay = {
    name       = "Allow the sanctioned SMTP relay"
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
    name       = "Block direct outbound SMTP"
    type       = "network"
    action     = "block"
    precedence = 110
    match      = { destination_ports = [25, 465, 587], protocols = ["tcp"] }
  }
}
```

Swap those two numbers and the relay stops working, with nothing in the plan to
suggest why.

### Ops name things; the layer writes the wirefilter

Gateway's API takes expressions - `any(app.ids[*] in {606})`,
`any(dns.security_category[*] in {68 80})`. The numbers are undocumented anywhere
an operator would look, they change as Cloudflare adds categories and
applications, and a wrong one is a rule that silently matches nothing.

So an account tree names things and `catalogue_lookup.tf` resolves them against
the account at plan time, the same way `account_governance` resolves permission
group names. An unrecognised category fails the plan listing every valid name; an
unrecognised application fails it too, with a pointer at the catalogue rather than
several hundred names inline.

`match` compiles to:

```
( destination terms OR'd ) and ( each remaining constraint AND'd )
```

Destination terms are the alternative ways of naming one thing - `domains`,
`hosts`, `applications`, `content_categories`, `security_categories`,
`destination_ip_cidrs`, and `sni_domains` / `sni_hosts` on a network policy.
Constraints narrow it: `source_ip_cidrs`, `destination_ports`, `protocols`,
`http_methods`, `dlp_profile_ids`, and the upload and download file types.
`negate` inverts the lot, which is how a default-deny with a carve-out is one rule
rather than two.

`identity` scopes a policy to people rather than traffic - a policy with an
identity condition and no traffic condition is perfectly valid, and is how
"contractors browse through isolation" is written. Group names are the ones the
identity provider sends, so for Entra ID that needs `support_groups` on the
provider in the `zerotrust` layer.

A selector the layer does not model goes in `traffic_expression`,
`identity_expression` or `device_posture_expression` as raw wirefilter. It
replaces the compiled expression rather than adding to it, and no guardrail can
see inside one.

### The Microsoft 365 bypass, and what it costs

`action = "off"` is Do Not Inspect: the connection is passed through without TLS
decryption. Microsoft 365 needs it because several of its clients pin
certificates and break under inspection.

```hcl
gateway_baseline_policies   = ["bypass_trusted_applications"]
gateway_bypass_applications = ["Microsoft 365"]
```

Naming the application rather than its hostnames means Cloudflare maintains the
list - a hostname Microsoft adds next month is covered without a pull request.

Two things follow, and both are the reason this is a named baseline rather than a
line somebody adds quietly. Cloudflare evaluates every Do Not Inspect policy
**before** all other HTTP policies, so a bypass outranks the DLP and quarantine
rules whatever their precedence. And nothing inside a bypassed application is
inspected, logged in detail or matched by a DLP profile - a bypass is a channel
data can leave through unexamined, which is precisely what the rest of this layer
exists to prevent.

The plan refuses a Do Not Inspect policy that matches on anything only visible
after decryption - a DLP profile, a method, a file type. Cloudflare does not
report that as an error: the rule simply never matches, the traffic keeps being
decrypted, and the dashboard shows the bypass as configured.

### DLP

A DLP profile is defined in the Zero Trust dashboard under DLP and referenced by
UUID. Cloudflare exposes no data source that resolves one by name, so this is the
one place in the layer where an opaque identifier is unavoidable.

```hcl
gateway_baseline_policies = ["block_dlp_matches"]
gateway_dlp_profile_ids   = ["<profile uuid>"]
```

A match is produced by scanning the decrypted request body, so DLP works on HTTP
policies only, and only where the traffic is actually inspected. The plan refuses
a DLP selector on a DNS or network policy, and refuses one paired with `off` or
`noscan`.

### Governing defaults

| Setting | Default | Effect |
|---|---|---|
| `reserved_precedence_ceiling` | `100` | An account tree policy claiming a lower precedence fails the plan. Below it belongs to the baseline, and Gateway stops at the first match. |
| `restricted_actions` | `[]` | Actions the layer refuses, named in the plan. Empty because the action worth the most thought - `off` - is also what a Microsoft 365 deployment needs. Set `["off"]` where inspection is never to be turned off outside the baseline. |
| `allow_dlp_payload_logging` | `false` | A policy setting `payload_log_enabled` fails the plan. Payload logging stores the fragment that triggered the DLP match - which is the sensitive data the policy exists to protect - in Cloudflare's logs, readable by everyone with log access. Useful while tuning a profile; not something to leave on. |
| `allow_disabling_dnssec_validation` | `false` | Disabling DNSSEC validation makes that policy's resolution spoofable. The usual cause is a badly signed internal zone, which is a problem to fix at the zone. |
| `allow_untrusted_certificate_pass_through` | `false` | `pass_through` serves a site whose certificate did not validate with no warning and no log entry, so an expired internal certificate and an interception attempt look identical. |
| `default_untrusted_cert_action` | `"error"` | Declared on every HTTP allow policy that sets nothing of its own, so a dashboard change shows up as drift. |
| `default_block_notification` | enabled, with a message | Applied to any block policy that sets no notification. The alternative to telling somebody why a request failed is a ticket saying "the internet is broken" and a user who finds another network. |

### Baseline catalogue

Opted into by name from `gateway_baseline_policies`, parameterised entirely by
variables so the same rule serves every account. The catalogue is in
`layers/gateway/locals.gateway.tf`.

| Name | Type | Action | Requires |
|---|---|---|---|
| `block_security_threats` | dns | block | `gateway_security_categories` |
| `block_security_threats_http` | http | block | `gateway_security_categories` |
| `block_disallowed_content` | dns | block | `gateway_blocked_content_categories` |
| `bypass_trusted_applications` | http | off | `gateway_bypass_applications` |
| `block_dlp_matches` | http | block | `gateway_dlp_profile_ids` |
| `quarantine_risky_downloads` | http | quarantine | `gateway_quarantine_file_types` |

**A baseline whose input is empty fails the plan**, for the same reason the WAF
baseline does: an empty set renders as `in {}`, which Cloudflare rejects as a
syntax error, and a bypass rule naming no application would sit in the dashboard
looking like a control while exempting nothing.

Cloudflare's file sandbox accepts a fixed and fairly short list of formats -
`exe`, `pdf`, `doc`, `docm`, `docx`, `rtf`, `ppt`, `pptx`, `xls`, `xlsm`, `xlsx`,
`zip`, `rar`. It is shorter than the set a policy can *match* on, so `dll` and
`scr` are rejected. Select the traffic with `match.download_file_types` and
quarantine only what the sandbox can detonate.

### What this layer does not hold

No Gateway lists, DLP profiles, proxy endpoints, account-level Gateway settings,
browser isolation controls, header injection, egress policies or resolver
policies. No WARP device enrolment or device posture checks either - a posture
check is referenced here by ID and defined elsewhere.

And no Access applications, identity providers or service tokens: those are the
`zerotrust` layer, with their own state and their own token. The split is
deliberate. The credential that decides what leaves the network is not the
credential that decides who gets into it.

## Cloudflare WAN

Cloudflare WAN, until recently Magic WAN: the GRE and IPsec tunnels between the
customer's sites and Cloudflare's edge, and the static routes that decide what
goes down them. Read a plan from this layer as a change to a network rather than
to a website - a destroy here takes a site off the network, and a changed route
sends its traffic somewhere else.

Ops name tunnels by key, and the layer resolves the routing:

```hcl
wan_ipsec_tunnels = {
  london_primary = {
    name                = "lon-ipsec-01"
    cloudflare_endpoint = "192.0.2.10"      # the anycast IP Cloudflare allocated
    customer_endpoint   = "203.0.113.10"    # the firewall's public IP
    interface_address   = "10.252.0.0/31"   # Cloudflare's side of the /31
  }
}

wan_static_routes = {
  london_lan_primary = {
    prefix     = "10.10.0.0/16"
    tunnel_key = "london_primary"
    priority   = 100
  }
}
```

### The next hop is the one thing not to write by hand

A tunnel is numbered from a /31, two hosts: the address in `interface_address`
is **Cloudflare's** end, and the other one is the customer device's. A static
route's next hop has to be the customer's. Point it at Cloudflare's own address
and the API accepts it, the dashboard shows the route as configured, and the
traffic is discarded.

That is why routes take `tunnel_key` rather than `nexthop`. The layer derives the
address from the tunnel, and a hand-written `nexthop` that matches no tunnel in
the layer fails the plan unless `allow_static_routes_to_unmanaged_nexthops` is
set.

### This layer does not enable Cloudflare WAN

It is an Enterprise entitlement, switched on by Cloudflare when it is bought.
There is no resource that could turn it on, and an account without it fails every
call in this layer on authorisation rather than on quota. Ordering the product is
a conversation, not a pull request.

Magic Transit and Magic Firewall are deliberately out of scope. Magic Transit
advertises your own public prefixes through Cloudflare and Magic Firewall filters
packets at the edge; both are separate products with their own blast radius, and
this layer's token holds no permission for the latter at all.

### Secrets

An IPsec pre-shared key **never goes in a tfvars file**. It reaches Terraform as
`TF_VAR_wan_ipsec_tunnel_psks`, a map keyed the same way as `wan_ipsec_tunnels`,
read from the layer's apply environment:

```bash
export TF_VAR_wan_ipsec_tunnel_psks='{"london_primary":"<psk>"}'
```

The same applies to `TF_VAR_wan_bgp_md5_keys` for a tunnel that peers over BGP,
though that one is credential-shaped rather than a credential: Cloudflare's own
documentation says MD5 is not a valid security mechanism and the key is not
treated as a secret. It prevents misconfiguration, not attack.

The PSK is different, and this layer's state should be treated accordingly. A
PSK is the whole of a tunnel's authentication, it reaches state in plain text
whatever route it takes - Cloudflare stores it, Terraform records what it sent -
and the endpoint addresses it pairs with are in the same file. Treat a leak as a
network compromise rather than a configuration disclosure, and rotate every key
in it at both ends. One key per tunnel, 32 or more random characters, never
reused between tunnels or sites.

Leave a tunnel out of the map entirely and Cloudflare generates a key it never
hands back. That is a legitimate choice - arguably a better one - but the
dashboard becomes the only copy, so the far end has to be configured from there.

### Governing defaults

| Setting | Default | Effect |
|---|---|---|
| `allow_tunnels_without_health_checks` | `false` | A tunnel setting `health_check_enabled = false` fails the plan. Health checks are the whole of the failover: Cloudflare withdraws an unhealthy tunnel from the Magic routing table, and with checks off the route stays and traffic keeps being sent into a tunnel that is down. |
| `allow_single_tunnel_prefixes` | `false` | A prefix reachable over exactly one tunnel fails the plan. One tunnel is a single point of failure with a health check attached - the check notices, and there is nowhere for the traffic to go. Cloudflare's guidance is at least two per site. |
| `allow_default_static_route` | `false` | A `0.0.0.0/0` or `::/0` route fails the plan. It sends everything Cloudflare has no more specific route for towards the customer network, which matches every destination nobody thought about. |
| `allow_public_static_route_prefixes` | `false` | A prefix outside RFC 1918, RFC 6598 or IPv6 unique-local space fails the plan. Cloudflare WAN routes between your own sites; advertising public space through Cloudflare is Magic Transit, which is a different product. |
| `allow_static_routes_to_unmanaged_nexthops` | `false` | A `nexthop` belonging to no tunnel in this layer fails the plan, naming the addresses that do. The usual cause is an address one out. |
| `default_tunnel_health_check_*` | enabled, `mid`, `reply`, `unidirectional` | Declared on every tunnel rather than left to Cloudflare's defaults, so switching a health check off in the dashboard shows up as drift. |
| `default_static_route_priority` | `100` | Two routes for one prefix at the same priority load-share across both tunnels. Give the standby a higher number where one path is genuinely preferred. |

### What this layer does not hold

No Magic Firewall rules, no Magic Transit prefixes, and no configuration for the
device at the customer end. A tunnel is half a tunnel until somebody configures
the far side to match, and Terraform cannot tell "not configured yet" from
"broken" - the health check can, which is why it is on by default.

## Adding a new account

1. `mkdir accounts/<name>/`, copy the ten tfvars files from `account_a`.
2. Set `cloudflare_account_id`, the zone inventory, and the per-layer config.
3. Provision a scoped API token per layer, and a state key prefix `<name>/`.
4. Add the account to the pipeline matrix.

No `.tf` changes.

## Adding a new product layer

1. `mkdir layers/<product>/`, named after the Cloudflare product it manages.
2. Add `terraform.tf`, `providers.tf` (documenting the minimum token scope),
   `variables.tf`, `locals.tf`, `<subject>.tf`, `outputs.tf`.
3. If it binds to a zone, copy `zone_lookup.tf` and the `referenced_zones` local
   so it resolves keys by name rather than reading another layer's state.
4. Add `preflight.tf` for any new key reference.
5. Add `accounts/*/<product>.tfvars` and extend the pipeline matrix.
6. If it must run after another layer, express that in the pipeline's stage
   dependencies — not in the directory name.

The module it calls should still make sense to someone who has never seen this
directory.
