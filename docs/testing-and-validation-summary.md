# Testing and Validation

All changes to the Cloudflare Landing Zone go through automated GitHub Actions pipelines. Testing happens at two levels: each reusable Terraform module is tested in its own repository, and the management repository tests the full deployment before anything reaches a live Cloudflare account. Nothing is deployed automatically. Every change to Cloudflare needs an explicit, human-approved run.

## 1. Module repositories: per-module CI

Each Terraform module (WAF, DNS, Zero Trust and so on) lives in its own versioned repository. Every pull request and every merge to `main` runs these checks. None of them use Cloudflare credentials or touch a Cloudflare account.

| Check | What it verifies |
|---|---|
| **Formatting** (`terraform fmt`) | Code meets the canonical Terraform style. |
| **Validation** (`terraform init` / `validate`) | The module and every example configuration in `examples/` are syntactically and semantically valid. All failures are reported in one run, not just the first. |
| **Offline plan** | A full `terraform plan` runs against the module's example inputs with no live account. This exercises every expression, loop and input validation rule using realistic values. Modules that must read live Cloudflare data at plan time are reported as skipped, not passed. |
| **Secret scanning** | Described in section 3. |
| **Release tagging** | After all checks pass on `main`, the module is tagged with its next semantic version (`vX.Y.Z`), set by the change type in the commit messages (major, minor or patch). The deployment pins each module to a specific tag, so untested code can never be consumed. |

## 2. Management repository: continuous integration

The CI pipeline runs on every pull request and every merge to `main`. It uses no Cloudflare credentials and makes no changes to Cloudflare.

| Check | What it verifies |
|---|---|
| **Formatting** | All Terraform conforms to `terraform fmt`. |
| **Linting** (TFLint) | Every layer is linted against a repository-wide ruleset, catching problems such as deprecated syntax and unused declarations. |
| **Validation** | Every deployment layer is initialised and validated against the pinned module versions. |
| **Offline plan** | Layers that can be planned without reading the live account are planned against each affected customer account's configuration. Only the account/layer combinations touched by the change are planned. If no layer remains offline-plannable, the pipeline fails rather than passing without checking anything. |
| **Configuration guards** | Every account configuration file is consumed by at least one layer, so no setting can be silently ignored. Remote-state backend blocks stay out of committed code. Sensitive files (state files, plan files, local secret variable files) cannot be committed, and the files the deployment needs are not accidentally excluded. |
| **Pipeline self-test** | The logic that decides which layers to plan and apply, and in what order, is tested against expected results. For example, a change to one layer's configuration must select only that layer, and the dependency ordering (account governance first, then zones, then zone-dependent services) must hold. A regression here fails the pull request. |
| **API rate limiter test** | The component that keeps pipeline traffic within Cloudflare's API rate limits has its own unit tests. |
| **Release tagging** | After all checks pass on `main`, the repository is tagged with its next semantic version. |

## 3. Secret scanning

Secret scanning runs on every pull request and every merge to `main`, in the management repository and in every module repository. A module cannot be released while a finding is open.

- **Betterleaks** scans the full Git history using its default ruleset plus custom rules for Cloudflare API tokens. The scanner binary is pinned to a specific version and checked against a known SHA-256 checksum before it runs.
- A second, stricter guard checks every tracked file, and the lines a pull request adds, for any Cloudflare API token prefix.
- Findings appear redacted in the pipeline summary, and a redacted report is kept for 7 days for triage. Any finding fails the pipeline.

## 4. Plan and apply: controlled deployment

Changes reach Cloudflare only through two manually started pipelines. Merging code never deploys anything.

### Terraform Plan (read-only)

- Produces a live plan against the customer's Cloudflare account using a read-only API token. It can be run against any branch before a change is merged.
- Publishes a summary of the resource changes (resource addresses and actions only, no configuration values). It raises a warning if any resource would be destroyed.

### Terraform Apply (approval-gated)

- Generates a plan, stores it, and waits for a named reviewer to approve that exact plan. The apply then runs the approved plan file. Terraform rejects a saved plan if the underlying state has changed since, so what is applied cannot differ from what was reviewed.
- There is no automatic approval and no destroy pipeline.
- Changes roll out in three dependency tiers: account governance, then zones and account-level services, then zone-dependent services. Each tier is planned only after the previous tier has applied.
- Each layer uses its own least-privilege Cloudflare API token, held in a dedicated GitHub Environment restricted to the `main` branch. For example, the WAF token cannot modify DNS or delete a zone.

### Drift Detection (nightly, read-only)

- Every night, a read-only plan runs against every account and layer, using the same read-only token as Terraform Plan. It can change nothing at Cloudflare.
- It reports resources changed outside Terraform (for example a dashboard edit), changes merged to `main` but never applied, and any layer it could not check.
- Findings go to one GitHub issue, which can be assigned to engineers or a service desk account. The issue opens when drift first appears, gets a comment only when the drift changes, and closes when everything matches again, so the same drift does not alert every night.
- The issue lists resource addresses and actions only, no configuration values.

### Pre-flight safeguards on every plan and apply

- The API token's format is checked before Terraform starts, and the token is verified against the target account.
- All Cloudflare API traffic goes through a rate limiter that stays within Cloudflare's published limits and retries throttled requests automatically. Its statistics are reported at the end of each run.
- Plan files are kept only briefly, because they contain configuration detail.
- Terraform state is stored per account and per layer in Cloudflare R2 with locking enabled. A change to one layer therefore cannot affect resources owned by another, and two concurrent runs cannot corrupt the same state.

## 5. Operational maintenance pipelines

Two manually started pipelines support state maintenance. Neither holds Cloudflare credentials, both default to a dry run, and both require the same reviewer approval as an apply.

- **State Unlock** releases a state lock left behind by an interrupted run.
- **State Forget** removes a resource from Terraform state without deleting it from Cloudflare, for example when moving ownership of a resource between layers.
