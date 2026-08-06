# `deployment` - the deployment template

Everything you edit lives here. The modules under [../modules/](../modules/) stay agnostic: flat arguments, real IDs, one resource group each, no knowledge of accounts, keys or profiles. You should avoid editing ".tf" files, as this is designed to be an upstream/downstream method. E.g. You have your sample Repo; this is then copied to a target account Repo, where you then make edits to the .tfvars files to match the target accounts; changes to .tf or modules should happen in the upstream repo, then propagated to downstream repos.

## Directory Structure

```deployment/
├── layers/                            # code, shared by every account
│   ├── zones/                         # own state: zones, settings, DNS
│   ├── waf/                           # own state: firewall + rate limiting
│   ├── load_balancing/                # own state: monitors, pools, LBs
│   ├── account_governance/            # own state: members, user groups
│   └── zerotrust/                     # own state: Access, policies, tokens, IdPs
└── accounts/                          # config, one tree per Cloudflare account
    ├── account_a/
    │   ├── account.tfvars             # account id       -> every layer
    │   ├── zones.tfvars               # zone inventory   -> zones, waf, load_balancing
    │   ├── dns.tfvars                 # zone config      -> zones
    │   ├── waf.tfvars                 # policies         -> waf
    │   ├── load_balancing.tfvars      # load balancers   -> load_balancing
    │   ├── account_governance.tfvars  # dashboard access -> account_governance
    │   └── zerotrust.tfvars           # Access           -> zerotrust
    └── account_b/
        └── ...
```

Each layer is a root module with its own state, holding `terraform.tf`, `providers.tf`, `variables.tf`, `locals*.tf`, one `<subject>.tf`, `preflight.tf`, `outputs.tf` and its own `defaults.auto.tfvars`.

Layers are named after the Cloudflare product they manage, with no ordering prefix. There is only one real dependency and it is not a chain:

```
zones ──┬── waf
        └── load_balancing        (waf and load_balancing are independent)

account_governance                (no zone involved, so no dependency at all)
zerotrust                         (same, but see below)
```

`waf` and `load_balancing` have no relationship to each other, so numbering them would assert a sequence that does not exist. `account_governance` touches no zone, so it neither creates nor resolves one and can apply whenever. `zerotrust` holds no zone in its state either, but an Access application only ever sees a request if the DNS record for its hostname exists and is proxied - so `zones` in practice comes first, and the failure if it does not is a login page nobody can reach rather than a Terraform error. Ordering is enforced where it can actually be enforced - pipeline stage dependencies, and the fact that both dependent layers resolve a zone by name and fail if it is absent - not by a filename that merely hints at it.

## Why split this way

**Account > separate layer run.** One `provider "cloudflare"` block carries one API token, and Terraform cannot pass a dynamic provider alias to a `for_each`'d module. So accounts cannot be `for_each` keys - each account is its own run, with its own token and its own state key. That is also the isolation you want: a token compromised for one customer cannot reach another.

**Product > separate state.**  A WAF or load balancer apply cannot propose destroying a zone, because zones are not in its state. Zone deletion is the worst blast radius in Cloudflare — it takes every DNS record with it. It also lets each layer's pipeline identity hold a narrower token: waf needs `Zone WAF:Edit` + `Zone:Read`, never `Zone:Edit`. The split cuts the other way too: `account_governance` is the only layer whose token can hand somebody else access to the Cloudflare account, and `zerotrust` the only one whose token can hand somebody access to what sits behind Access. Neither holds anything at zone scope in exchange.

**Zone > a `for_each` key, not a directory.** A directory per account×zone would
mean adding a zone requires adding `.tf` code, duplicated N×M, and a fleet-wide
version bump would touch N×M module sources. Adding a zone here is two edits to
`zones.tfvars` and `dns.tfvars`.

## Layers do not read each other's state

The waf and load_balancing layers resolve a zone key to a zone ID with `data "cloudflare_zone"` filtered by name, not `terraform_remote_state`. The states stay independent - either layer can be applied, re-inited or relocated without the other noticing.

The cost is real and worth knowing: those layers call the Cloudflare API at plan time, so **only `zones` can be planned offline**, and the other two fail if the zone does not exist yet. Apply `zones` first; `waf` and `load_balancing` can then run in either order, or concurrently. `account_governance` reads the API too - it resolves role and permission group names to IDs - and so does `zerotrust`, which reads the account's existing Zero Trust organization so it can adopt the team name rather than demand one. Neither waits on another layer. CI validates every layer offline and plans only `zones` without credentials.

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

`waf` takes `account.tfvars`, `zones.tfvars`, `waf.tfvars`. `load_balancing` takes `account.tfvars`, `zones.tfvars`, `load_balancing.tfvars`. `account_governance` takes `account.tfvars` and `account_governance.tfvars`, and no zone inventory at all. `zerotrust` takes `account.tfvars` and `zerotrust.tfvars`, plus `TF_VAR_identity_provider_secrets` in the environment for any identity provider that authenticates against an OAuth application.

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

`preflight.tf` in each layer catches what neither variable validation nor a module block can: a `zone_key` pointing at nothing, a `zone_config` key with no matching zone, two WAF policies fighting over one zone, a load balancer hostname outside its zone's domain, and a user group naming a member who was never declared. All fail the plan with the offender named.

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

## Adding a new account

1. `mkdir accounts/<name>/`, copy the seven tfvars files from `account_a`.
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
