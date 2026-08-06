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
  zone exists. Today: `zones` and `account_governance` first, then `waf` and
  `load_balancing` concurrently. `account_governance` is in the first tier because
  it touches no zone at all, not because anything waits on it.

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
two accounts and four layers that is ten environments.

| Environment                          | Reviewers    | `CLOUDFLARE_API_TOKEN` scope                                                                                                                                    |
| -------------------------------------| --------------| -----------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `account_a-plan`                     | none         | read-only: `Zone:Read`, `DNS:Read`, `Zone Settings:Read`, `Zone WAF:Read`, `Account Load Balancers:Read`, `Zone Load Balancers:Read`, `Account Settings:Read` |
| `account_a-zones-apply`              | **required** | `Zone:Edit`, `DNS:Edit`, `Zone Settings:Edit`                                                                                                                    |
| `account_a-waf-apply`                | **required** | `Zone WAF:Edit`, `Zone:Read`, notably *not* `Zone:Edit`                                                                                                         |
| `account_a-load_balancing-apply`     | **required** | `Account Load Balancers:Edit`, `Zone Load Balancers:Edit`, `Zone:Read`                                                                                          |
| `account_a-account_governance-apply` | **required** | `Account Settings:Edit`, and nothing at zone scope                                                                                                              |

…and the same for `account_b`. Each token is scoped to **one account and one
layer**: the scopes are the ones documented in each layer's `providers.tf`, and
splitting them is the reason the layers were split in the first place. A WAF
token cannot delete a zone.

The `account_governance` token deserves separate thought. `Account Settings:Edit`
is what invites members and creates user groups, which makes it the only token in
the set that can grant somebody else access to the account. It holds nothing at
zone scope in exchange, so it cannot touch DNS or a firewall rule, but treat its
reviewer list as the tightest of the four.

On the apply environments, also set **Deployment branches** to `main` only, so a
branch cannot reach a write token.

## Branch protection

Mark **`plan complete`** as the required status check, not `plan`. The `plan` job
is legitimately skipped when a change affects no account, and a skipped job can
never satisfy a required check.

## Operating notes

**A PR that adds a new zone *and* its WAF or load balancer config in one change
will fail the `waf` / `load_balancing` plans.** Those layers resolve the zone via
`data "cloudflare_zone"`, and it does not exist yet.

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
