# Pipelines

Four workflows, plus one reusable definition they all share.

| Workflow                                     | Trigger                                | Touches Cloudflare? | Can change anything? |
| ----------------------------------------------| ----------------------------------------| ---------------------| ----------------------|
| [`ci.yml`](ci.yml)                           | every PR, every push to `main`         | no                  | no                   |
| [`secret-scanning.yml`](secret-scanning.yml) | every PR, every push to `main`, manual | no                  | no                   |
| [`terraform-plan.yml`](terraform-plan.yml)   | PR touching the Terraform tree, manual | reads               | no                   |
| [`terraform-apply.yml`](terraform-apply.yml) | manual only                            | reads + writes      | yes, after approval  |
| [`_terraform-run.yml`](_terraform-run.yml)   | called by the two above                | n/a                 | n/a                  |

## Apply never runs without a plan

`terraform-apply.yml` is started by hand only - it has no `push` trigger, so merging
to `main` never applies anything. When you are ready, run it from the Actions tab.

It plans first, uploads the plan file, waits for a human, then
runs `terraform apply <that plan file>`. There is no `-auto-approve` in this
repository. The reviewer approves a specific plan, and Terraform refuses a saved
plan whose state has moved since, so an apply cannot quietly diverge from what
was reviewed.

There is deliberately **no destroy path**. Destroying a zone takes every DNS
record in it.

## What gets run, and in what order

Nothing is hardcoded. [`tf-matrix.sh`](../scripts/tf-matrix.sh) and
[`tf-varfiles.sh`](../scripts/tf-varfiles.sh) read the answers out of the
Terraform source, so adding an account, a layer or a module needs no edit here:

- **Which pairs are affected**, from the changed files. A change to
  `accounts/account_a/waf.tfvars` plans the `waf` layer for `account_a` and
  nothing else; a change to `modules/zone_base/` plans every layer that calls
  that module, for every account.
- **Which var files a layer takes**: a var file belongs to a layer when every
  top-level variable it assigns is declared by that layer. This works because
  `deployment/README.md` guarantees no two files in an account tree assign the
  same variable.
- **Apply order**, as three sequential tiers. Everything within a tier runs
  concurrently; each tier is *planned* only after the previous one has *applied*.

  | Tier | Layers | Why it is here |
  |---|---|---|
  | 1 | `account_governance` | Account-wide permissions and resource-group scope. Every later tier's token is evaluated against what this applies, so it goes out on its own and first. |
  | 2 | `zones`, `bulk_redirects`, `gateway`, `wan`, `zerotrust` | `zones` *creates* zones. The rest touch no zone at all, so nothing waits on them - they ride along in this tier rather than being ordered against each other. |
  | 3 | `waf`, `load_balancing`, `r2`, `workers` | Resolve a zone with `data "cloudflare_zone"`, which fails at plan time until tier 2 has created it. `r2` is here because a bucket can be served from a custom domain, even where no bucket currently is. |

  Tier 2 and 3 membership is **derived from the Terraform source** - `zone_base`
  call versus `data "cloudflare_zone"` block - so a new layer classifies itself.
  Tier 1 is the exception: no Terraform reference expresses "authz must land
  first", so it is the `PREREQ_LAYERS` list in
  [`tf-matrix.sh`](../scripts/tf-matrix.sh). Keep that list short.

`ci.yml` asserts all three, so a regression in the derivation fails a PR rather
than silently causing a merged change never to be planned.

The one place the graph is not fully dynamic: a GitHub Actions job graph is
static YAML and cannot grow a stage at runtime, so `terraform-apply.yml` declares
three tier stages. If a new layer makes the graph deeper, both `discover` and
`ci.yml` fail with instructions instead of skipping the extra tier.

## Remote state

State lives in Cloudflare R2 through Terraform's S3-compatible backend, one state
object per `{account, layer}` pair:

```
<TF_BACKEND_BUCKET>/
  Your-Org/zones.tfstate
  Your-Org/waf.tfstate
  Your-Org/gateway.tfstate
  ...one key per layer directory
```

The key is derived, not configured: `STATE_KEY` in
[`_terraform-run.yml`](_terraform-run.yml) is `<account>/<layer>.tfstate`. That
split is the reason a `waf` apply cannot propose destroying a zone - zones are not
in its state.

**Leave the `backend "s3"` block in each layer's `terraform.tf` commented out.**
It is committed as documentation only. `ci.yml` runs `init -backend=false` so
validation needs no R2 credentials, and `_terraform-run.yml` writes the real block
to `backend.generated.tf` at run time, passing bucket, key and endpoint as
`-backend-config` flags so no state location is ever committed. Uncommenting the
block gives two backend blocks and fails the run - the generate step checks for
this and errors with an explanation rather than letting Terraform emit its own
unhelpful message.

Nothing needs pre-creating beyond the bucket itself. The first apply for a pair
writes its state object; there is no bootstrap step and no import.

Locking is `use_lockfile = true`, which uses S3 conditional writes - supported by
R2, and the reason every layer requires Terraform >= 1.11. R2 has no DynamoDB
equivalent, so this plus the per-state-key `concurrency` group is the whole of the
protection against two concurrent applies corrupting one key.

R2 has no object versioning, so there is no rollback for a state object. Take
periodic copies of the bucket if state loss would be expensive to reconstruct.

Every layer's state holds resource attributes in plain text, including values
Cloudflare returns for tunnel secrets, service tokens and WAF expressions. The
bucket is a secret store: no public access, no public bucket URL, no custom
domain, and the R2 token below scoped to it alone.

## Required configuration

### Repository variables

| Name | Example | Notes |
|---|---|---|
| `TF_BACKEND_BUCKET` | `Your-Org-cloudflare-platform-tfstate` | R2 bucket holding state, see [Remote state](#remote-state). |
| `TF_BACKEND_ENDPOINT` | `https://<state-account-id>.r2.cloudflarestorage.com` | S3-compatible R2 endpoint. |
| `MODULES_APP_ID` | `1234567` | App ID of the modules-reader GitHub App below. Not a secret. |

### Repository secrets

| Name                      | Notes                                                                            |
| ---------------------------| ----------------------------------------------------------------------------------|
| `R2_ACCESS_KEY_ID`        | R2 API token, **Object Read & Write on this bucket only**.                       |
| `R2_SECRET_ACCESS_KEY`    | Its secret.                                                                      |
| `MODULES_APP_PRIVATE_KEY` | The modules-reader App's private key, PEM including the header and footer lines. |

### Reading the private modules repository

Every layer sources its modules from
`<org>/cloudflare-platform-modules`, which is private.
`GITHUB_TOKEN` is scoped to this repository alone, so `terraform init` cannot
clone it and fails with `could not read Username for 'https://github.com'`.

[`../actions/modules-auth`](../actions/modules-auth/action.yml) fixes that: it
mints a GitHub App installation token per run and rewrites `https://github.com/`
in the runner's git config to carry it. It runs in every job that inits -
`_terraform-run.yml`, and `validate` and `offline-plan` in `ci.yml`.

To create the App, once, at organisation level:

1. **Org settings → Developer settings → GitHub Apps → New GitHub App.** Name it
   something like `cf-terraform-modules-reader`. Untick Webhook → Active.
2. **Repository permissions: Contents → Read-only.** Nothing else. It needs no
   account permissions and no write anywhere.
3. Generate a private key, put the PEM in `MODULES_APP_PRIVATE_KEY`, and the App
   ID in `MODULES_APP_ID`.
4. **Install the App on the Module Repositories only** - "Only select
   repositories". Installing it org-wide would give every workflow here read
   access to every repository in the org.

A token is minted fresh per job, expires within the hour, and is revoked by the
action's post step. Nothing is tied to an individual, so nobody leaving breaks
the pipeline, and there is no PAT expiry to diarise.

An App token is preferred over a fine-grained PAT precisely because of step 4:
the PAT equivalent would be long-lived, owned by a person, and only as narrow as
whoever last edited it remembered to make it.

### Environments

Per account: **one plan environment, plus one apply environment per layer.** For
two accounts and eight layers that is eighteen environments.

| Environment                          | Reviewers    | `CLOUDFLARE_API_TOKEN` scope                                                                                                                                                                                                    |
| --------------------------------------| --------------| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `account_a-plan`                     | none         | read-only: `Zone:Read`, `DNS:Read`, `Zone Settings:Read`, `Zone WAF:Read`, `Account Load Balancers:Read`, `Zone Load Balancers:Read`, `Workers R2 Storage:Read`, `Account Settings:Read`, `Zero Trust:Read`                     |
| `account_a-zones-apply`              | **required** | `Zone:Edit`, `DNS:Edit`, `Zone Settings:Edit`                                                                                                                                                                                   |
| `account_a-waf-apply`                | **required** | `Zone WAF:Edit`, `Zone:Read`, notably *not* `Zone:Edit`                                                                                                                                                                         |
| `account_a-load_balancing-apply`     | **required** | `Account Load Balancers:Edit`, `Zone Load Balancers:Edit`, `Zone:Read`                                                                                                                                                          |
| `account_a-r2-apply`                 | **required** | `Workers R2 Storage:Edit` at account scope; plus `Zone:Read` and `Zone DNS:Edit` only if a bucket has a custom domain                                                                                                           |
| `account_a-account_governance-apply` | **required** | `Account Settings:Edit`, and nothing at zone scope                                                                                                                                                                              |
| `account_a-zerotrust-apply`          | **required** | `Access: Organizations, Identity Providers, and Groups:Edit`, `Access: Apps and Policies:Edit`, `Access: Service Tokens:Edit`, all at account scope                                                                             |
| `account_a-gateway-apply`            | **required** | `Zero Trust:Edit` at account scope, and nothing else. The API refers to the same grant as Zero Trust Write; it covers both the Gateway policy APIs and the category and application catalogues the layer resolves names against |
| `account_a-wan-apply`                | **required** | `Magic Transit:Edit` at account scope, and nothing else. The permission group is named after the older product and covers the Cloudflare WAN tunnel and route APIs                                                              |

…and the same for `account_b`. Each token is scoped to **one account and one
layer**: the scopes are the ones documented in each layer's `providers.tf`, and
splitting them is the reason the layers were split in the first place. A WAF
token cannot delete a zone.

Every run checks the token's shape before `terraform init` - see "Check the API
token is a well-formed bearer credential" in
[`_terraform-run.yml`](_terraform-run.yml). Whitespace in the value, or a global
API key (`cfk_`) where a token belongs, fails the job immediately; anything else
is a warning and the run continues. This exists because Cloudflare answers a
malformed `Authorization` header with 6003/6111 "Invalid format for
Authorization header" - a header parse error thrown before the token is looked
up, so it looks nothing like a credential problem and no amount of scope fixes
it. Terraform reports it per-resource as "failed to make http request", which on
a large layer means waiting out most of a plan for an answer that had nothing to
do with the layer. Set the secret by piping the value in, never by pasting it as
an argument, and re-copy from the token's own reveal view rather than from
anywhere it may have been line-wrapped.

`Workers R2 Storage:Edit` is a control-plane permission: it creates, configures and deletes buckets, but it
cannot read or write a single object. Object access goes through an R2 access
key, which is a separate S3 credential that this repository deliberately never
creates or holds - see [../../deployment/README.md](../../deployment/README.md).
The exception is `R2_ACCESS_KEY_ID` below, which is scoped to the state bucket
alone.

The `account_governance` token deserves separate thought. `Account Settings:Edit`
is what invites members and creates user groups, which makes it the only token in
the set that can grant somebody else access to the Cloudflare account. It holds
nothing at zone scope in exchange, so it cannot touch DNS or a firewall rule, but
treat its reviewer list as the tightest of the set.

The `gateway` token is the third. `Zero Trust:Edit` can rewrite the egress filter
in either direction: it can block what people reach, and - the one that matters -
it can add a Do Not Inspect policy, which stops a channel being decrypted, logged
in detail or matched by a DLP profile. That change looks like one more rule in a
plan and is the difference between data exfiltration being visible and not, so
read this layer's diffs for what they stop watching as much as for what they
stop. The token holds nothing at zone scope and cannot reach Access.

The `zerotrust` token is the other one to think about. `Access: Organizations,
Identity Providers, and Groups:Edit` can change the team name, add a login method
and rewrite every Access group, which is enough to reach everything sitting
behind Access - the internal systems rather than the Cloudflare dashboard. Give
it the same reviewer list as `account_governance`.

The `zerotrust` apply environment also carries one secret no other environment
does: **`TF_VAR_IDENTITY_PROVIDER_SECRETS`**, a JSON object of OAuth client
secrets keyed the same way as the `identity_providers` map, exported as
`TF_VAR_identity_provider_secrets` for the run.

```
TF_VAR_IDENTITY_PROVIDER_SECRETS = {"entra_id":"<Entra app registration client secret>"}
```

It is a GitHub Environment secret rather than a repository secret, so it is
scoped to the one account it belongs to, and it never appears in a `.tfvars`
file. It does reach Terraform state in plain text - Cloudflare stores it and
Terraform records what it sent - which is why this layer's state and its plan
files are treated as credential material. See
[../../deployment/README.md](../../deployment/README.md).

The `wan` apply environment carries secrets on the same terms, and for the same
reasons. **`TF_VAR_WAN_IPSEC_TUNNEL_PSKS`** is a JSON object of IPsec pre-shared
keys keyed the same way as the `wan_ipsec_tunnels` map, exported as
`TF_VAR_wan_ipsec_tunnel_psks` for the run, and
**`TF_VAR_WAN_BGP_MD5_KEYS`** does the same for BGP session keys where any tunnel
peers.

```
TF_VAR_WAN_IPSEC_TUNNEL_PSKS = {"london_primary":"<psk>","london_secondary":"<psk>"}
```

A PSK is the whole of a tunnel's authentication, and the tunnel endpoints it
pairs with are in the same state file, so treat a leak of `wan` state as a
network compromise: rotate every key in it, at both ends. One key per tunnel,
32 or more random characters, never reused between tunnels or sites.

`TF_VAR_WAN_BGP_MD5_KEYS` is credential-shaped and belongs in an environment
secret for that reason alone. It is not a security control - Cloudflare's own
documentation says MD5 is not a valid security mechanism and the key is not
treated as a secret. It stops accidental peering, not an attacker.

Neither variable is wired into [`_terraform-run.yml`](_terraform-run.yml), and
nor is `TF_VAR_IDENTITY_PROVIDER_SECRETS`: exporting an unset environment secret
would hand Terraform an empty string where it expects a map and fail the run for
every layer that does not need one. Export them in the run step of your own copy
of that workflow, conditionally on the secret being set.

On the apply environments, also set **Deployment branches** to `main` only, so a
branch cannot reach a write token.

## Branch protection

Mark **`plan complete`** as the required status check, not `plan`. The `plan` job
is legitimately skipped when a change affects no account, and a skipped job can
never satisfy a required check.

## Operating notes

**A PR that adds a new zone *and* its WAF, load balancer or R2 custom domain
config in one change will fail the `waf` / `load_balancing` / `r2` plans.** Those
layers resolve the zone via `data "cloudflare_zone"`, and it does not exist yet.

Split it into two pull requests: the zone first, then whatever depends on it. By the
time the second is planned the zone exists and the lookup resolves.

`terraform-apply.yml` does not have this problem. `plan-tier2` depends on
`apply-tier1`, so tier 3 is planned only after the zone has been created, and a single
apply run handles both changes together unaided. It is the pull request
plan that cannot succeed early, and since `plan complete` is a required check that is
what blocks the merge. A manual per layer apply run is not needed for this.

**Every apply run is manual, and a manual run has no diff to filter against**, so it
selects every pair allowed by the `account` / `layer` inputs. `all` / `all` means the
whole fleet, so narrow it to the account and layer you actually reviewed a plan for.
The same is true of a `workflow_dispatch` run of `terraform-plan.yml`.

**Lint rules live in [`.tflint.hcl`](../../.tflint.hcl) at the repository root**,
and `ci.yml` passes it to `tflint` by absolute path so `--recursive` keeps using
it as it descends into each layer instead of silently linting with defaults. It
sets `call_module_type = "local"` because the `lint` job deliberately does not
run `terraform init`, so no remote module is on disk to descend into.

**An account tfvars that assigns nothing is legal.** For example if `load_balancing.tfvars` is
commented-out, it is kept as a template. `tf-varfiles.sh` skips such
a file - passing it to Terraform buys nothing - and the orphan guard in `ci.yml`
skips it for the same reason. A file that assigns real variables that no layer
declares is still an error.

## Adding an account or a layer

Adding an **account**: create `deployment/accounts/<name>/`, then create the
environments (`<name>-plan` and one `<name>-<layer>-apply` per layer) with their
scoped tokens. No workflow edit.

Adding a **layer**: create `deployment/layers/<product>/`, add
`accounts/*/<product>.tfvars`, and create a `<account>-<product>-apply`
environment per account. No workflow edit, unless the layer introduces a fourth
dependency tier, in which case `ci.yml` will tell you to add a stage pair to
`terraform-apply.yml`.
