# Pipelines

Three workflows, plus one reusable definition they all share.

| Workflow                                     | Trigger                                | Touches Cloudflare? | Can change anything? |
| ----------------------------------------------| ----------------------------------------| ---------------------| ----------------------|
| [`ci.yml`](ci.yml)                           | every PR, every push to `main`         | no                  | no                   |
| [`terraform-plan.yml`](terraform-plan.yml)   | PR touching the Terraform tree, manual | reads               | no                   |
| [`terraform-apply.yml`](terraform-apply.yml) | push to `main`, manual                 | reads + writes      | yes, after approval  |
| [`_terraform-run.yml`](_terraform-run.yml)   | called by the two above                | n/a                 | n/a                  |

## Apply never runs without a plan

`terraform-apply.yml` plans first, uploads the plan file, waits for a human, then
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
- **Apply order**: a layer that *creates* zones must apply before a layer that
  *looks one up* with `data "cloudflare_zone"`, since that read fails until the
  zone exists. Today: `zones`, `account_governance`, `wan` and `zerotrust`
  first, then `waf`, `load_balancing` and `r2` concurrently. `account_governance`,
  `wan` and `zerotrust` are in the first tier because they touch no zone at all,
  not because anything waits on them. `r2` is in the second because a bucket can
  be served from a custom domain, even where no bucket currently is.

`ci.yml` asserts all three, so a regression in the derivation fails a PR rather
than silently causing a merged change never to be planned.

The one place the graph is not fully dynamic: a GitHub Actions job graph is
static YAML and cannot grow a stage at runtime, so `terraform-apply.yml` declares
two tier stages. If a new layer makes the graph deeper, both `discover` and
`ci.yml` fail with instructions instead of skipping the extra tier.

## Required configuration

### Repository variables

| Name | Example | Notes |
|---|---|---|
| `TF_BACKEND_BUCKET` | `cf-lz-tfstate` | R2 bucket holding state. |
| `TF_BACKEND_ENDPOINT` | `https://<state-account-id>.r2.cloudflarestorage.com` | S3-compatible R2 endpoint. |

### Repository secrets

| Name | Notes |
|---|---|
| `R2_ACCESS_KEY_ID` | R2 API token, **Object Read & Write on this bucket only**. |
| `R2_SECRET_ACCESS_KEY` | Its secret. |

### Environments

Per account: **one plan environment, plus one apply environment per layer.** For
two accounts and seven layers that is sixteen environments.

| Environment                          | Reviewers    | `CLOUDFLARE_API_TOKEN` scope                                                                                                                                    |
| -------------------------------------| --------------| -----------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `account_a-plan`                     | none         | read-only: `Zone:Read`, `DNS:Read`, `Zone Settings:Read`, `Zone WAF:Read`, `Account Load Balancers:Read`, `Zone Load Balancers:Read`, `Workers R2 Storage:Read`, `Account Settings:Read` |
| `account_a-zones-apply`              | **required** | `Zone:Edit`, `DNS:Edit`, `Zone Settings:Edit`                                                                                                                    |
| `account_a-waf-apply`                | **required** | `Zone WAF:Edit`, `Zone:Read`, notably *not* `Zone:Edit`                                                                                                         |
| `account_a-load_balancing-apply`     | **required** | `Account Load Balancers:Edit`, `Zone Load Balancers:Edit`, `Zone:Read`                                                                                          |
| `account_a-r2-apply`                 | **required** | `Workers R2 Storage:Edit` at account scope; plus `Zone:Read` and `Zone DNS:Edit` only if a bucket has a custom domain                                            |
| `account_a-account_governance-apply` | **required** | `Account Settings:Edit`, and nothing at zone scope                                                                                                              |
| `account_a-zerotrust-apply`          | **required** | `Access: Organizations, Identity Providers, and Groups:Edit`, `Access: Apps and Policies:Edit`, `Access: Service Tokens:Edit`, all at account scope             |
| `account_a-wan-apply`                | **required** | `Magic Transit:Edit` at account scope, and nothing else. The permission group is named after the older product and covers the Cloudflare WAN tunnel and route APIs |

…and the same for `account_b`. Each token is scoped to **one account and one
layer**: the scopes are the ones documented in each layer's `providers.tf`, and
splitting them is the reason the layers were split in the first place. A WAF
token cannot delete a zone.

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
treat its reviewer list as the tightest of the five.

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

`terraform-apply.yml` does not have this problem. `plan-tier1` depends on
`apply-tier0`, so tier 2 is planned only after the zone has been created, and if both
changes do reach `main` together the run handles it unaided. It is the pull request
plan that cannot succeed early, and since `plan complete` is a required check that is
what blocks the merge. A manual per layer apply run is not needed for this.

**A manual run has no diff to filter against**, so it selects every pair allowed
by the `account` / `layer` inputs. `all` / `all` means the whole fleet, so narrow it.

## Adding an account or a layer

Adding an **account**: create `deployment/accounts/<name>/`, then create the
environments (`<name>-plan` and one `<name>-<layer>-apply` per layer) with their
scoped tokens. No workflow edit.

Adding a **layer**: create `deployment/layers/<product>/`, add
`accounts/*/<product>.tfvars`, and create a `<account>-<product>-apply`
environment per account. No workflow edit, unless the layer introduces a third
dependency tier, in which case `ci.yml` will tell you to add a stage pair to
`terraform-apply.yml`.
