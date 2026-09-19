# Variables & Secrets

Quick reference for every GitHub variable and secret the pipelines read: what it
is, which layer needs it, and where it goes. For the reasoning behind any of
it - token scopes, security trade-offs, rate limiting - see
[.github/workflows/README.md](.github/workflows/README.md).

## At a glance

| # | What | Where it goes | How many |
|---|---|---|---|
| 1 | [Repository variables](#1-repository-variables) | Repo **Settings → Secrets and variables → Actions → Variables** | 3 |
| 2 | [Repository secrets](#2-repository-secrets) | Repo **Settings → Secrets and variables → Actions → Secrets** | 3 |
| 3 | [Environments](#3-environments) | Repo **Settings → Environments** | 2 + one per layer, per account |
| 4 | [`CLOUDFLARE_API_TOKEN`](#4-cloudflare_api_token---one-per-environment) | Environment secret, in **every** environment | 1 per environment |
| 5 | [Layer secrets (`TF_VAR_*`)](#5-layer-secrets-tf_var_) | Environment secret, `<account>-plan` | Only for layers that use them |

`<account>` is a directory name under [deployment/accounts/](deployment/accounts/),
e.g. `account_a`. `<layer>` is a directory name under
[deployment/layers/](deployment/layers/), e.g. `waf`.

Nothing here goes in a `.tf` or `.tfvars` file.

---

## 1. Repository variables

Not secret. Shared by every account and layer.

| Name | Example | What it is | Read by |
|---|---|---|---|
| `TF_BACKEND_BUCKET` | `yourorg-cloudflare-platform-tfstate` | R2 bucket that holds Terraform state | plan, apply, `state-forget`, `state-unlock` |
| `TF_BACKEND_ENDPOINT` | `https://<state-account-id>.r2.cloudflarestorage.com` | S3-compatible endpoint for that bucket | plan, apply, `state-forget`, `state-unlock` |
| `MODULES_APP_ID` | `1234567` | Numeric App ID of the modules-reader GitHub App (not the client ID or slug) | every workflow, `ci.yml` included |

## 2. Repository secrets

Shared by every account and layer.

| Name | What it is | Read by |
|---|---|---|
| `R2_ACCESS_KEY_ID` | R2 API token ID, **Object Read & Write on the state bucket only** | plan, apply, `state-forget`, `state-unlock` |
| `R2_SECRET_ACCESS_KEY` | That token's secret | plan, apply, `state-forget`, `state-unlock` |
| `MODULES_APP_PRIVATE_KEY` | The modules-reader App's private key - the whole `.pem`, header and footer lines included | every workflow, `ci.yml` included |

The GitHub App needs **Contents: Read-only** and nothing else, installed on the
private modules repository only (`cloudflare-platform-modules` by default - the
`repository` input of [modules-auth](.github/actions/modules-auth/action.yml)).
Setup steps: [Reading the private modules repository](.github/workflows/README.md#reading-the-private-modules-repository).

## 3. Environments

Per account, you need **one plan environment, one apply environment per layer,
and one for the resource tags job** - two more than there are directories under
`deployment/layers/`.

| Environment | Reviewers | Deployment branches | Created by |
|---|---|---|---|
| `<account>-plan` | none | any (manual plans run from feature branches) | **you, by hand** |
| `<account>-<layer>-apply` | **required** | `main` only | [`bootstrap-environments.sh`](.github/scripts/bootstrap-environments.sh) |
| `<account>-tags-apply` | none - it only tags what an approved apply just output | `main` only | [`bootstrap-environments.sh`](.github/scripts/bootstrap-environments.sh) |

```bash
# Creates every <account>-<layer>-apply environment found in the tree, gated and
# main-only, plus <account>-tags-apply, main-only with no reviewers
REVIEWER_TEAMS="cf-admins" bash .github/scripts/bootstrap-environments.sh
```

Re-run it whenever you add a layer or an account. `state-forget.yml` and
`state-unlock.yml` run inside the `<account>-<layer>-apply` environments for
their reviewer gate only - they need nothing extra.

## 4. `CLOUDFLARE_API_TOKEN` - one per environment

Every environment holds its **own** `CLOUDFLARE_API_TOKEN`, scoped to one account
and one layer. Never reuse one token across two environments - that undoes the
layer split.

[`bootstrap-account-tokens.sh`](.github/scripts/bootstrap-account-tokens.sh)
creates most of them as account-owned tokens and writes them to a CSV. The
**Bootstrap token** column shows which CSV row goes in which environment. Delete
the CSV once they are all uploaded.

| Environment | Layer | Bootstrap token | Minimum scope |
|---|---|---|---|
| `<account>-plan` | all (plan only) | `terraform-plan` | Read-only, account and zone scope |
| `<account>-account_governance-apply` | `account_governance` | `terraform-accountgovernance-apply` | `Account Settings:Edit` |
| `<account>-bulk_redirects-apply` | `bulk_redirects` | *not created - make by hand* | `Account Filter Lists:Edit`, `Account Rulesets:Edit` |
| `<account>-device_posture-apply` | `device_posture` | `terraform-deviceposture-apply` | `Zero Trust:Edit` |
| `<account>-dns-apply` | `dns` | `terraform-dns-apply` | `DNS:Edit`, `Zone:Read` |
| `<account>-gateway-apply` | `gateway` | `terraform-gateway-apply` | `Zero Trust:Edit` |
| `<account>-lists-apply` | `lists` | *not created - make by hand* | `Account Filter Lists:Edit` |
| `<account>-load_balancing-apply` | `load_balancing` | `terraform-loadbalancing-apply` | `Account Load Balancers:Edit`, `Zone Load Balancers:Edit`, `Zone:Read` |
| `<account>-logpush-apply` | `logpush` | `terraform-logpush-apply` | `Logs:Edit` (account + zone), `Zone:Read`; `Zero Trust: PII Read` for Access/Gateway/DEX datasets |
| `<account>-origin_pulls-apply` | `origin_pulls` | `terraform-originpulls-apply` | `SSL and Certificates:Edit`, `Zone:Read` - notably *not* `Zone:Edit` and *not* `DNS:Edit` |
| `<account>-r2-apply` | `r2` | `terraform-r2-apply` | `Workers R2 Storage:Edit`; `Zone:Read` + `DNS:Edit` if a bucket has a custom domain |
| `<account>-rules-apply` | `rules` | *not created - make by hand* | Not yet documented in the layer's `providers.tf`. Needs edit on the zone-level cache, late transform and origin ruleset phases, and `Zone:Read` |
| `<account>-tags-apply` | none - the resource tags job | `terraform-tags-apply` | Resource Tagging write at account scope, plus zone scope for zone tags. Beta groups, found by name - never `Access: Tags` |
| `<account>-tunnels-apply` | `tunnels` | `terraform-tunnels-apply` | `Cloudflare Tunnel:Edit`; `Zone:Read` + `DNS:Edit` if a hostname is published |
| `<account>-turnstile-apply` | `turnstile` | `terraform-turnstile-apply` | `Turnstile:Edit` (the API names the same grant Turnstile Sites Write). Reaches widgets and nothing else - but reading a widget returns its secret key, so it is not a low-value credential |
| `<account>-waf-apply` | `waf` | `terraform-waf-apply` | `Zone WAF:Edit`, `Zone:Read` |
| `<account>-wan-apply` | `wan` | `terraform-wan-apply` | `Magic Transit:Edit` |
| `<account>-workers-apply` | `workers` | `terraform-workers-apply` | `Workers Scripts:Edit`, `Workers KV Storage:Edit`, `Zone:Read`; `D1:Edit` if databases are declared; `Queues:Edit` if queues are declared; `Workers Routes:Edit` if routes are declared; `DNS:Edit` for a custom domain. `D1:Edit` also carries query execution over the D1 REST API, so it can read and rewrite the contents of every database in the account |
| `<account>-zerotrust-apply` | `zerotrust` | `terraform-zerotrust-apply` | `Access: Organizations, Identity Providers, and Groups:Edit`, `Access: Apps and Policies:Edit`, `Access: Service Tokens:Edit` |
| `<account>-zones-apply` | `zones` | `terraform-zone-apply` | `Zone:Edit`, `DNS:Edit`, `Zone Settings:Edit` |

Scopes come from each layer's `providers.tf` where it documents them, and from
the resources the layer manages where it does not.

The bootstrap tokens are not an exact match for this column. Several are
broader - notably `terraform-wan-apply`, `terraform-workers-apply` and
`terraform-zerotrust-apply` - and `terraform-waf-apply` has no `Zone:Read`.
Run the script with `DRY_RUN=1` to see exactly what each token would get.

## 5. Layer secrets (`TF_VAR_*`)

Only five layers take a secret besides their token. Each is a JSON object keyed
the same way as the matching map in that layer's `.tfvars`.

These go in the **`<account>-plan`** environment, not the apply one. The plan
step is what reads `TF_VAR_*`; apply runs the saved plan and never re-reads them.

| Secret name | Layer | Keyed like | Wired into the pipeline? | Example value |
|---|---|---|---|---|
| `TF_VAR_IDENTITY_PROVIDER_SECRETS` | `zerotrust` | `identity_providers` | Yes, on every plan - **must be set**, `{}` if none | `{"entra_id":"<client secret>"}` |
| `TF_VAR_DEVICE_POSTURE_INTEGRATION_SECRETS` | `device_posture` | `device_posture_integrations` | Yes, only when set | `{"intune":{"client_secret":"<client secret>"}}` |
| `TF_VAR_LOGPUSH_DESTINATION_SECRETS` | `logpush` | `logpush_jobs` | Yes, only when set | `{"audit_archive":"r2://<bucket>/audit/{DATE}?account-id=<id>&access-key-id=<key id>&secret-access-key=<secret>"}` |
| `TF_VAR_LOGPUSH_OWNERSHIP_CHALLENGES` | `logpush` | `logpush_jobs` | Yes, only when set | `{"primary_http_requests":"<challenge token>"}` |
| `TF_VAR_ORIGIN_PULL_CERTIFICATES` | `origin_pulls` | `certificate_key` references in `origin_pulls` | Yes, only when set | `{"api_origin":{"certificate":"-----BEGIN CERTIFICATE-----\n...","private_key":"-----BEGIN PRIVATE KEY-----\n..."}}` |
| `TF_VAR_WAN_IPSEC_TUNNEL_PSKS` | `wan` | `wan_ipsec_tunnels` | **No** - see below | `{"london_primary":"<psk>","london_secondary":"<psk>"}` |
| `TF_VAR_WAN_BGP_MD5_KEYS` | `wan` | `wan_gre_tunnels` / `wan_ipsec_tunnels` | **No** - see below | `{"london_primary":"<md5 key>"}` |

Notes:

- **Only set what you use** - except the `zerotrust` one. An empty
  `logpush_jobs`, `device_posture_integrations` or `wan_ipsec_tunnels` needs no
  secret. The plan fails for a secret keyed to something that is not declared.
- **zerotrust:** the pipeline exports `TF_VAR_IDENTITY_PROVIDER_SECRETS` on
  every plan, set or not. Unset, it reaches Terraform as an empty string and the
  `zerotrust` plan fails with `Missing expression`. With no identity provider
  secrets, set it to `{}`.
- **device_posture:** most integration types take `client_secret`; Uptycs takes
  `client_key` and `client_secret`; a custom integration takes
  `access_client_secret`.
- **origin_pulls:** only needed where a zone uploads a client certificate of
  its own; a zone running on the certificate Cloudflare presents by default
  needs nothing here. PEM is line-structured, so the newlines have to survive -
  build the value with `jq -n --rawfile cert x.crt --rawfile key x.key` rather
  than pasting. Both the certificate and its private key land in that layer's
  state in plain text, and the private key is an identity the origin has been
  told to trust.
- **logpush:** a destination whose URI carries a credential (R2, Splunk HEC,
  Datadog, Azure SAS) goes in `TF_VAR_LOGPUSH_DESTINATION_SECRETS` and is left
  out of `logpush.tfvars`. One with no credential (S3, GCS) stays in
  `destination_conf`.
- **wan:** neither WAN secret is exported by
  [`_terraform-run.yml`](.github/workflows/_terraform-run.yml). Add a
  conditional export to the plan step in your copy, the same way the
  `device_posture` and `logpush` ones are done, before populating
  `wan_ipsec_tunnels`. One PSK per tunnel, 32+ random characters, never reused.
- The `<account>-plan` environment has no reviewer gate, so anyone who can
  dispatch a plan can reach these. Every one also lands in the saved plan and in
  that layer's state in plain text. Scope each credential as narrowly as its
  provider allows.

### Layers with nothing extra

`account_governance`, `bulk_redirects`, `dns`, `gateway`, `lists`,
`load_balancing`, `r2`, `rules`, `tunnels`, `waf`, `workers` and `zones` need
only their `CLOUDFLARE_API_TOKEN`. So does `origin_pulls`, unless a zone in it
uploads a certificate of its own. Workers secrets live in Cloudflare Secrets
Store and are referenced by name in `workers.tfvars`.

---

## Setting a secret safely

Pipe the value in, or type it at the prompt. Never pass it as a command-line
argument: it ends up in shell history, and a stray newline or space makes
Cloudflare reject the token with 6003/6111.

```bash
# Prompts for the value
gh secret set CLOUDFLARE_API_TOKEN --repo <owner/repo> --env <account>-waf-apply

# JSON and PEM values: pipe from a file, then delete the file
gh secret set TF_VAR_LOGPUSH_DESTINATION_SECRETS --repo <owner/repo> --env <account>-plan < logpush.json
gh secret set MODULES_APP_PRIVATE_KEY --repo <owner/repo> < app.pem

# Repository variable
gh variable set TF_BACKEND_BUCKET --repo <owner/repo> --body "yourorg-cloudflare-platform-tfstate"
```

```powershell
# PowerShell: -Raw keeps the PEM's newlines intact
Get-Content app.pem -Raw | gh secret set MODULES_APP_PRIVATE_KEY --repo <owner/repo>
```

## Bootstrap script inputs

These are shell variables for running the bootstrap scripts on your own machine.
They are **not** stored in GitHub.

| Script | Variable | Required | What it is |
|---|---|---|---|
| `bootstrap-account-tokens.sh` | `CLOUDFLARE_ACCOUNT_ID` | yes (prompts) | Target account ID |
| | `CLOUDFLARE_USER_TOKEN` | yes (prompts) | User API token with `Account API Tokens:Edit`. Delete it afterwards. |
| | `CSV_OUTPUT_PATH` | no (prompts) | Where to write the token CSV |
| | `ONLY_TOKEN` | no | Create one token only, e.g. `terraform-waf-apply` |
| | `DRY_RUN` | no | `1` = print payloads, create nothing |
| `bootstrap-environments.sh` | `REVIEWER_TEAMS` or `REVIEWER_USERS` | one of them, unless `ONLY_LAYER=tags` | Space-separated team slugs or usernames |
| | `PREVENT_SELF_REVIEW` | no (default `true`) | Needs a second reviewer to be workable |
| | `WAIT_TIMER` | no (default `0`) | Minutes before approval is offered |
| | `DEPLOY_BRANCH` | no (default `main`) | Only branch allowed to apply |
| | `ONLY_LAYER` | no | Create environments for one layer only, or `tags` for the tags environment |
| | `REPO` | no | `owner/name`, defaults to the origin remote |
| | `DRY_RUN` | no | `1` = print changes, touch nothing |

## Not a GitHub setting

The Cloudflare account ID is configuration, not a secret. It goes in
`deployment/accounts/<account>/account.tfvars` as `cloudflare_account_id`, and
every layer reads it from there.

## When a run says something is missing

| Error in the run                                                                             | Fix                                                                                            |
| ----------------------------------------------------------------------------------------------| ------------------------------------------------------------------------------------------------|
| `missing secret CLOUDFLARE_API_TOKEN (environment '<name>')`                                 | Add the token to that environment ([section 4](#4-cloudflare_api_token---one-per-environment)) |
| `missing secret R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY`                                   | Repository secrets ([section 2](#2-repository-secrets))                                        |
| `missing variable TF_BACKEND_BUCKET` / `TF_BACKEND_ENDPOINT`                                 | Repository variables ([section 1](#1-repository-variables))                                    |
| `variable MODULES_APP_ID is not numeric`                                                     | Use the App ID, not the client ID or slug                                                      |
| `MODULES_APP_PRIVATE_KEY has no -----BEGIN ... PRIVATE KEY----- line` or `is 1 line(s) long` | Re-set the secret by piping the whole `.pem` in                                                |
| `Malformed API token` / `contains whitespace`                                                | Re-set the token by piping it in, from the token's own reveal view                             |
| `Wrong credential type` / `cfk_ prefix`                                                      | That is a Global API Key. Create an API token instead.                                         |
| `Missing expression` on `<value for var.identity_provider_secrets>`                          | Set `TF_VAR_IDENTITY_PROVIDER_SECRETS` in `<account>-plan` - `{}` if there are none            |
| `Token did not verify` (warning)                                                             | Token revoked, expired, or scoped to a different account                                       |
