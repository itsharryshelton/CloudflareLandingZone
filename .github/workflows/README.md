# Pipelines

Six workflows, plus one reusable definition the Terraform ones share.

| Workflow                                     | Trigger                                | Touches Cloudflare? | Can change anything? |
| ----------------------------------------------| ----------------------------------------| ---------------------| ----------------------|
| [`ci.yml`](ci.yml)                           | every PR, every push to `main`         | no                  | no                   |
| [`secret-scanning.yml`](secret-scanning.yml) | every PR, every push to `main`, manual | no                  | no                   |
| [`terraform-plan.yml`](terraform-plan.yml)   | manual only                            | reads               | no                   |
| [`terraform-apply.yml`](terraform-apply.yml) | manual only                            | reads + writes      | yes, after approval  |
| [`state-forget.yml`](state-forget.yml)       | manual only                            | no                  | state only, after approval |
| [`state-unlock.yml`](state-unlock.yml)       | manual only                            | no                  | the state lock only, after approval |
| [`_terraform-run.yml`](_terraform-run.yml)   | called by plan and apply               | n/a                 | n/a                  |

The two `state-*` workflows are maintenance tools with **no automated caller**.
Neither holds a Cloudflare credential, so neither can change anything at
Cloudflare - see their headers.

`state-forget.yml` makes Terraform forget a resource without deleting it, which
is what hands a resource from one layer's state to another's. Kept because the
layer split that created the `dns` layer will not be the last one.

`state-unlock.yml` releases a state lock left behind by a run that was cancelled
while holding it - the `PreconditionFailed` on every subsequent plan for that
account and layer. See ["A cancelled run left the state
locked"](#a-cancelled-run-left-the-state-locked).

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
  | 2 | `zones`, `bulk_redirects`, `gateway`, `lists`, `wan` | `zones` *creates* zones. The rest touch no zone at all, so nothing waits on them - they ride along in this tier rather than being ordered against each other. `lists` must land before `waf`, which it does by being a tier earlier. |
  | 3 | `dns`, `load_balancing`, `logpush`, `r2`, `rules`, `tunnels`, `waf`, `workers`, `zerotrust` | Resolve a zone with `data "cloudflare_zone"`, which fails at plan time until tier 2 has created it. `r2` is here because a bucket can be served from a custom domain, even where no bucket currently is; `tunnels` for the same reason, since a tunnel's public hostname needs a CNAME in its zone; `logpush` because a zone-scoped job is created against its zone, even on an account whose jobs are all account-scoped. `zerotrust` is here by `POST_ZONE_LAYERS` instead: Access applications are addressed by hostname, so they need the zone to exist even though the layer never reads one. |

  Tier 2 and 3 membership is **derived from the Terraform source** - `zone_base`
  call versus `data "cloudflare_zone"` block - so a new layer classifies itself.
  Tier 1 is the exception: no Terraform reference expresses "authz must land
  first", so it is the `PREREQ_LAYERS` list in
  [`tf-matrix.sh`](../scripts/tf-matrix.sh). Keep that list short.

`ci.yml` asserts all three, so a regression in the derivation fails a PR rather
than silently causing a merged change never to be planned.

## API rate limiting

Cloudflare allows **1200 API requests per five minutes per credential**. The
`zones` layer holds one `cloudflare_zone`, one `cloudflare_zone_rules` and a
handful of `cloudflare_zone_setting` resources per zone, and every one of them is
a GET on every refresh — so at a few hundred zones a single plan is several
thousand reads. Terraform issues those as fast as its scheduler allows.

The Cloudflare provider used to pace itself: `rps`, `retries`, `min_backoff` and
`max_backoff` were provider arguments in 4.x. The 5.x rewrite dropped all four
and never replaced them, so a 5.x provider has **no rate limiting and no 429
retry at all** ([cloudflare/terraform-provider-cloudflare#5505](https://github.com/cloudflare/terraform-provider-cloudflare/issues/5505)).
Without something in front of it, a large layer fails partway through with

```
429 {"code":971,"message":"Please wait and consider throttling your request speed"}
```

reported as `failed to make http request` against whichever resource was in
flight.

`_terraform-run.yml` therefore starts
[`cf-api-throttle.py`](../scripts/cf-api-throttle.py) after `init` and points the
provider at it with `CLOUDFLARE_BASE_URL`. It is a loopback HTTP listener that
paces every request through a shared token bucket and retries any 429 that still
gets through, honouring the API's own `Retry-After`. 
Terraform sees a slow API rather than a rate-limited one.

Two inputs tune it, both with defaults that suit this account's zone count:

| Input | Default | What it does |
|---|---|---|
| `api_rps` | `3.5` | Sustained requests per second. 1200/5min is 4.0/s; 3.5 leaves headroom for anything else using the same token. `0` bypasses the limiter entirely — debugging only. |
| `parallelism` | `4` | Terraform's `-parallelism`. Secondary: it caps concurrent resources, not request rate. It exists so a run whose limiter died degrades gently instead of burning the budget in a minute. |

The consequence is that plans and applies on `zones` are **slow by design**. The
rate limit sets a floor: a refresh of *n* resources cannot finish faster than
`n / api_rps` seconds, whatever the runner does. Raising `api_rps` above 4.0 does
not make it faster, it makes it fail.

Each job's `Stop the rate limiter` step publishes what the limiter absorbed —
request count, 429s retried, worst queue wait — to the job summary. **A non-zero
`429s_absorbed` means `api_rps` is too high for that credential**; a warning
about the limiter exiting early means Terraform went unpaced and any 429 in that
log has a different cause.

Two things do *not* go through it, both deliberately: `init` (which fetches
providers and modules from the registry and GitHub, not from Cloudflare) and the
post-apply `kv-bulk-load.sh` (which uses `wrangler`, and moves 15,000 keys in a
handful of bulk calls).

### Credential handling

Every proxied request carries the Cloudflare bearer token, so the limiter handles
a live credential. It binds `127.0.0.1` only — nothing off the runner can reach it.

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

The lock is therefore an object, `<account>/<layer>.tfstate.tflock`, sitting next
to the state. A run cancelled before it can delete that object leaves it behind
and blocks the pair - see ["A cancelled run left the state
locked"](#a-cancelled-run-left-the-state-locked).

R2 has no object versioning, so there is no rollback for a state object. Take
periodic copies of the bucket if state loss would be expensive to reconstruct.

Every layer's state holds resource attributes in plain text, including values
Cloudflare returns for tunnel secrets, service tokens and WAF expressions. The
bucket is a secret store: no public access, no public bucket URL, no custom
domain, and the R2 token below scoped to it alone.

## Required configuration

### Repository variables

| Name                  | Example                                               | Notes                                                        |
| -----------------------| -------------------------------------------------------| --------------------------------------------------------------|
| `TF_BACKEND_BUCKET`   | `yourorg-cloudflare-platform-tfstate`                 | R2 bucket holding state, see [Remote state](#remote-state).  |
| `TF_BACKEND_ENDPOINT` | `https://<state-account-id>.r2.cloudflarestorage.com` | S3-compatible R2 endpoint.                                   |
| `MODULES_APP_ID`      | `1234567`                                             | App ID of the modules-reader GitHub App below. Not a secret. |

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
| `account_a-plan`                     | none         | read-only: `Zone:Read`, `DNS:Read`, `Zone Settings:Read`, `Zone WAF:Read`, `Account Load Balancers:Read`, `Zone Load Balancers:Read`, `Workers R2 Storage:Read`, `Account Settings:Read`, `Zero Trust:Read`, `Logs:Read` at account and zone scope                     |
| `account_a-zones-apply`              | **required** | `Zone:Edit`, `DNS:Edit`, `Zone Settings:Edit`                                                                                                                                                                                   |
| `account_a-waf-apply`                | **required** | `Zone WAF:Edit`, `Zone:Read`, notably *not* `Zone:Edit`                                                                                                                                                                         |
| `account_a-load_balancing-apply`     | **required** | `Account Load Balancers:Edit`, `Zone Load Balancers:Edit`, `Zone:Read`                                                                                                                                                          |
| `account_a-r2-apply`                 | **required** | `Workers R2 Storage:Edit` at account scope; plus `Zone:Read` and `Zone DNS:Edit` only if a bucket has a custom domain                                                                                                           |
| `account_a-account_governance-apply` | **required** | `Account Settings:Edit`, and nothing at zone scope                                                                                                                                                                              |
| `account_a-zerotrust-apply`          | **required** | `Access: Organizations, Identity Providers, and Groups:Edit`, `Access: Apps and Policies:Edit`, `Access: Service Tokens:Edit`, all at account scope                                                                             |
| `account_a-tunnels-apply`            | **required** | `Cloudflare Tunnel:Edit` at account scope; plus `Zone:Read` and `DNS:Edit` only if an ingress rule publishes a hostname, for its proxied CNAME                                                                   |
| `account_a-logpush-apply`            | **required** | `Logs:Edit` at account and zone scope, and `Zone:Read`; plus `Zero Trust: PII Read` at account scope only if a job pushes an Access, Gateway or DEX dataset |
| `account_a-gateway-apply`            | **required** | `Zero Trust:Edit` at account scope, and nothing else. The API refers to the same grant as Zero Trust Write; it covers both the Gateway policy APIs and the category and application catalogues the layer resolves names against |
| `account_a-wan-apply`                | **required** | `Magic Transit:Edit` at account scope, and nothing else. The permission group is named after the older product and covers the Cloudflare WAN tunnel and route APIs                                                              |

…and the same for `account_b`. Each token is scoped to **one account and one
layer**: the scopes are the ones documented in each layer's `providers.tf`, and
splitting them is the reason the layers were split in the first place. A WAF
token cannot delete a zone.

`state-forget.yml` and `state-unlock.yml` run in the same
`<account>-<layer>-apply` environment, purely to borrow its reviewer gate. They
do not read `CLOUDFLARE_API_TOKEN` - it is absent from their `env` blocks - so
adding a layer needs no new environment for them.

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

The `tunnels` token is its counterpart, and deliberately a separate one.
`Cloudflare Tunnel:Edit` decides what is reachable at all: it can publish any
internal service on a public hostname, route any private range to any connector,
and - because the connector token endpoint accepts the same permission - fetch
the token that runs any tunnel on the account. It holds nothing from the Access
permission groups, so it cannot decide who gets in, and the `zerotrust` token in
turn cannot touch a tunnel. Between them they are the whole of what sits behind
Cloudflare One, so give both the same reviewer list. The layer never sends a
tunnel secret or reads a connector token, so its environment carries no
`TF_VAR_` secret and its state holds no credential that can run a connector.

The `logpush` token decides where logs go. `Logs:Edit` can point any dataset -
every request to every zone, every DNS query a Gateway user made - at any
destination it can name, and it can switch off the job a SOC depends on:
exfiltration and blinding in one grant. Jobs on Access, Gateway and DEX datasets
also need `Zero Trust: PII Read`, without which Cloudflare will not create,
change or delete them. It changes no traffic, but give it the same reviewer list
as `gateway` and `zerotrust`.

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

The `logpush` layer takes two secrets, and those are wired in:
[`_terraform-run.yml`](_terraform-run.yml) exports them for the `logpush` layer
only, and only when set - the conditional export described above - so an unset
secret never reaches Terraform as an empty string. They belong in the
**`<account>-plan`** environment, because the plan step is what reads them and
apply runs the saved plan without re-reading `TF_VAR_`:

```
TF_VAR_LOGPUSH_DESTINATION_SECRETS  = {"audit_archive":"r2://<bucket>/audit/{DATE}?account-id=<id>&access-key-id=<key id>&secret-access-key=<secret>"}
TF_VAR_LOGPUSH_OWNERSHIP_CHALLENGES = {"primary_http_requests":"<challenge token>"}
```

The first is the whole destination URI, keyed by job, for any job whose
destination carries a credential - R2 keys, a Splunk HEC token, a Datadog API
key, an Azure SAS. The second is the ownership challenge token for destinations
that ask for one. Both land in the saved plan and in `logpush` state in plain
text. The plan environment has no reviewer gate, so anyone who can dispatch a
plan can reach them - the same trade `TF_VAR_IDENTITY_PROVIDER_SECRETS` makes.
Scope each destination credential to the one bucket or index it writes to.

On the apply environments, also set **Deployment branches** to `main` only, so a
branch cannot reach a write token.

## No live plan on a pull request

`terraform-plan.yml` is **manual only**. It does not run on pull requests.

I removed this on purpose; when your zone file grows massively, it will take a long time for any PR to complete, testing against 250 domains, one PR check took 25 minutes to complete; when the PR didn't touch zones; this is because of the rate limiting we are needing to do. Plans & Apply are already gated at the Apply pipeline, so I deemed this low risk - you can always run plans against your branch before PR.

## Notes

**A manual plan of a new zone *and* its WAF, load balancer or R2 custom domain
config will fail the `waf` / `load_balancing` / `r2` plans.** Those layers resolve
the zone via `data "cloudflare_zone"`, and it does not exist yet. Preview the
`zones` layer only, or wait until the zone has been applied.

This never blocks a merge - it is a manual preview, and `ci.yml`'s offline plan
does not resolve zones. `terraform-apply.yml` does not have the problem either:
`plan-tier2` depends on `apply-tier1`, so tier 3 is planned only after the zone
has been created, and a single apply run handles both changes together unaided.

**A plan that removes a zone setting shows destroys, and they are safe.**
`cloudflare_zone_setting` has no delete operation — the provider's `Delete` is an
empty function — so a destroy drops the resource from Terraform state and leaves
the value exactly as it is at Cloudflare. Dropping one setting from the baseline
therefore plans one destroy per zone, which trips the `Warn on planned destroys`
step and its warning about zones taking their DNS records with them. Read the
resource addresses: `module.zones[...].cloudflare_zone_setting.this["..."]` is
this case, `module.zones[...].cloudflare_zone.this` is the dangerous one.

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

### A cancelled run left the state locked

Cancelling a plan or apply usually releases the lock on the way out. If the
runner is killed before it can, the lock object stays behind and every later run for that account and layer fails immediately:

```
Error: Error acquiring the state lock
Error message: operation error S3: PutObject, https response error StatusCode: 412
api error PreconditionFailed: At least one of the pre-conditions you specified did not hold.
Lock Info:
  ID:        0cad19f9-e895-589b-6622-33ddfc27a0ae
  Path:      <bucket>/Your-Org/dns.tfstate
  Operation: OperationTypePlan
```

The 412 is the backend's conditional write refusing to overwrite a lock that is
already there. Nothing is wrong with the state itself - a cancelled plan never writes state - so only the lock needs clearing:

1. Check the Actions tab for a still-running plan or apply for that pair. If
   there is one, the lock is real. Cancel that run and wait; it releases the
   lock itself. Compare the `Created` timestamp above against the clock -
   seconds old means live, not stale.
2. Run [`state-unlock.yml`](state-unlock.yml) with the account, the layer,
   the `ID` copied out of the error, and the layer name again as `confirm`.
   Leave `dry_run` ticked for the first run: it reports who took the lock and
   when, and releases nothing.
3. Re-run with `dry_run` unticked. It approves through the layer's
   `<account>-<layer>-apply` environment, like any state edit here.
4. Re-run the plan.

If it was an **apply** rather than a plan that died, read the next plan
carefully before approving it. The lock says nothing about how far the
interrupted apply got; the plan does.

## Adding an account or a layer

Adding an **account**: create `deployment/accounts/<name>/`, then create the
environments (`<name>-plan` and one `<name>-<layer>-apply` per layer) with their
scoped tokens. No workflow edit.

Adding a **layer**: create `deployment/layers/<product>/`, add
`accounts/*/<product>.tfvars`, and create a `<account>-<product>-apply`
environment per account.

No edit to `terraform-plan.yml` or `terraform-apply.yml` - both derive the work
from `tf-matrix.sh` - unless the layer introduces a fourth dependency tier, in
which case `ci.yml` will tell you to add a stage pair to `terraform-apply.yml`.

The **`ci.yml` self-test does need updating**, and this is easy to miss because
the plan and apply pipelines will already be doing the right thing. The step
asserts the derivation against expectations that name layers explicitly, so a new
layer turns it red until it is added to:

- the per-layer loop that checks a `<layer>.tfvars` change selects only that layer;
- the `zones.tfvars` expectation, if the layer declares the `zones` variable;
- the tier 3 expectation, if the layer resolves a zone through a data source.

That is deliberate. The self-test exists so a mistake in the derivation cannot
merge silently, and a new layer landing in the wrong tier is exactly the mistake
it is there to catch - so it asks to be told what the answer should be rather
than reading it back from the thing under test.
