# Contributing

This document is about changing the Terraform. If you only want to configure a
customer, you want the [Wiki](https://github.com/itsharryshelton/CloudflareLandingZone/wiki)
instead, and you should not need to touch a `.tf` file at all.

## Upstream and downstream

This repository is the upstream template. It gets copied to a per customer
repository, where operators edit `.tfvars` and nothing else.

That splits changes cleanly:

| Change | Where |
|---|---|
| A customer's domains, records, rules, origins | Downstream, in `deployment/accounts/` |
| Module logic, layer wiring, variable schemas, the WAF catalogue | Here, then propagated downstream by version |

If a customer needs something the schema cannot express, that is an upstream
change. Add the input here, tag a release, and let the downstream repository pick
it up. Do not special case one customer in their own copy: the next template update
will overwrite it, and nobody will remember why the file was different.

## Layout

```
modules/            agnostic building blocks, one Cloudflare concern each
deployment/
  layers/           root modules, one per product, each with its own state
  accounts/         configuration, one directory per Cloudflare account
.github/
  workflows/        CI, secret scanning, plan, apply, state maintenance
  scripts/          the derivation helpers CI depends on, plus the post-apply scripts
  actions/          modules-auth, which lets `terraform init` read the private modules
```

Two rules hold the whole thing together.

Modules know nothing about this repository. They take flat arguments and real IDs,
never logical keys, and they never iterate over the fleet. One module instance is
one resource group - one zone's records, one bucket, one tunnel - and any
`for_each` inside a module is over the members of that group only. That is what
lets a module be tagged, frozen and reused across every customer.

Layers own the fleet shaped view. They hold every variable, iterate `for_each` over
maps keyed by a logical key, and turn `zone_key = "primary"` into a zone ID.

## Module conventions

Four files, always, plus `versions.tf`. Copy [modules/_TEMPLATE/](modules/_TEMPLATE/)
to start. [modules/README.md](modules/README.md) has the full set of rules every
module follows, the module-to-layer map, and how modules are published and
versioned; this section is the short form.

| File | Holds |
|---|---|
| `variables.tf` | The operator facing schema, and every single field guardrail as a `validation` block |
| `locals.tf` | Normalisation and mapping onto provider shaped values |
| `main.tf` | Resource declarations, plus `lifecycle.precondition` for cross field rules |
| `outputs.tf` | IDs and values other layers bind to |
| `examples/basic/main.tf` | A root module calling `source = "../.."` with placeholder inputs. It is the fixture the published module repository's CI plans offline |

An example must stay offline-plannable: no data sources, every input a literal,
placeholders only. With no example, a module that has required inputs cannot be
planned by its own CI at all.

### Where a guardrail goes

Put a check in `variables.tf` if it can be decided from one variable. Types, enums,
ranges, required fields. It fails before Terraform builds a graph, and the message
points at exactly one input.

Put it in a `lifecycle.precondition` in `main.tf` if it needs another variable, a
local, or a comparison across list items.

Modules and layers both declare `required_version = ">= 1.12.0"`. That floor is
set by the modules, not the backend: guards such as `x == null || contains(list, x)`
rely on `||` and `&&` short-circuiting, which Terraform only does from 1.12. Before
1.12 both sides are evaluated, and the check fails on the very null it was meant to
skip. If a guard must hold on an older Terraform, write it as a conditional
(`x == null ? true : contains(list, x)`), which evaluates only the branch it takes.

A validation block has been able to reference another variable since 1.9, so that
is no longer a technical limit. Cross field checks in a module still go in a
`lifecycle.precondition`, so that every one of them is in `main.tf`. Cross
variable checks in a layer still live in `preflight.tf`, on a `terraform_data` resource, for
two reasons: a `module` block cannot carry a `lifecycle` block at all, and keeping
every cross cutting assertion in one file means a reader can see all of them
without opening four others. `terraform_data` needs no credentials and makes no API
calls.

So: single field checks go in `variables.tf` everywhere. Cross field checks go in
`main.tf` in a module, and `preflight.tf` in a layer.

### Duplicate object keys

A `for` expression that builds a map aborts on a duplicate key with Terraform's
generic `Duplicate object key`, pointing into `locals.tf`. It does not quietly keep
the last one. Group with `...`, take `[0]`, and report the collision through a
precondition so the operator gets a message naming the duplicate. See
`modules/zone_base/locals.tf`.

TFLint fails on unused locals under the `recommended` preset. A local that exists
only so variable validation could reference it will not survive, because validation
cannot reference locals anyway. Inline the list in the validation and leave a
comment saying why it is duplicated.

## Adding a module

1. Copy `modules/_TEMPLATE/` to `modules/<name>/`.
2. Fill in the four files and `examples/basic/main.tf`. Leave `versions.tf` alone,
   unless the module needs a newer provider than `~> 5.7` - as `ai_gateway` does -
   in which case say why in a comment there.
3. Document it in place. There are no per-module READMEs, on purpose: a separate
   document drifts from the code it describes, and
   [modules/README.md](modules/README.md) covers only what every module has in
   common. Add the new module to its table. Every variable carries a
   `description` saying what it does and what it accepts, TFLint enforces that,
   and the reasoning goes in the header comments of `locals.tf` and `main.tf`.
   Write those descriptions as though somebody will only ever read them from an
   editor's hover tooltip, because they will.
4. Call it from a layer, and add sample values to an account tree.
5. Push a branch and read what CI says.

Ask yourself whether the module would make sense to somebody who has never seen
`deployment/`. If it takes a `zone_key`, or reads a variable called
`waf_trusted_ip_ranges`, it has absorbed something that belongs in a layer.

## Adding a layer

1. `mkdir deployment/layers/<product>/`, named after the Cloudflare product.
   No numeric prefix. Ordering is derived, not spelled.
2. Add `terraform.tf`, `providers.tf`, `variables.tf`, `locals.tf`,
   `<subject>.tf`, `outputs.tf`.
3. Document the minimum API token scope in `providers.tf`. Somebody creating
   tokens will look there first.
4. If it binds to a zone, copy `zone_lookup.tf` and the `referenced_zones` local
   so it resolves keys by name instead of reading another layer's state. If it
   binds to something else Cloudflare identifies by an opaque per-account ID -
   roles, permission groups, resource groups - do the equivalent with a data
   source of its own, so an account tree never carries a hex string. See
   `account_governance/permission_lookup.tf`.
5. Add `preflight.tf` for any new key reference.
6. Add `accounts/*/<product>.tfvars`, and a `<account>-<product>-apply`
   environment per account.
7. If the product needs a credential of its own - a pre-shared key, an OAuth
   client secret - declare it as a `sensitive` variable that the account tree
   never assigns, and document that it arrives as `TF_VAR_<name>` from the
   `<account>-plan` environment, not the apply one: the plan step reads it, and
   apply runs the saved plan without re-reading `TF_VAR_`. Add a conditional
   export for it to the plan step of `_terraform-run.yml`, so an unset secret
   never reaches Terraform as an empty string. See `origin_pull_certificates` in
   `layers/origin_pulls/variables.tf`, and its export in `_terraform-run.yml`.
8. Add the layer to the `ci.yml` self-test, and give it a `tier.tf` only if the
   derived apply tier is wrong. See "Adding a new product layer" in
   [deployment/README.md](deployment/README.md).

## Adding an account

Create `deployment/accounts/<name>/` with the tfvars files, then create the
GitHub environments, `<name>-tags-apply` included. No workflow edit and no `.tf` edit. The scripts discover
accounts from the directory tree.

## Configuration rules

One variable, one file. Nothing in an account tree may assign a variable that
another file in the same tree also assigns.

This is not tidiness. `-var-file` does not merge: if two files both define `zones`,
the last one silently wins in full. It is also what makes the pipeline work, since
`tf-varfiles.sh` decides a file belongs to a layer when every variable it assigns is
declared by that layer. Break the rule and the mapping becomes ambiguous, which
`ci.yml` will catch.

Platform defaults live in `layers/<layer>/defaults.auto.tfvars`, auto loaded and
customer agnostic. Account values live in `accounts/<account>/` and win, because
they are passed later.

## What may be committed

Account IDs and domain names are committed. They are configuration, not secrets,
and this is acceptable only while the repository stays private with RBAC. **DO NOT COMMIT VARIABLE FILES WITH REAL DATA TO PUBLIC REPOS!**

Tokens and R2 keys are never committed, in any form, in any file. They reach
Terraform as `CLOUDFLARE_API_TOKEN`, `AWS_ACCESS_KEY_ID` and
`AWS_SECRET_ACCESS_KEY` at runtime.

`.gitignore` is default deny for `*.tfvars`, with explicit exceptions for
`layers/*/defaults.auto.tfvars` and `accounts/*/*.tfvars`. It then re-denies
`**/terraform.tfvars`, `**/local.auto.tfvars` and `**/*.local.tfvars` after those
exceptions, so no negation can reach them. `ci.yml` asserts both directions, and
fails if a state file, saved plan or local override is tracked.
`secret-scanning.yml` runs betterleaks over the whole git history and greps every
tracked file for a Cloudflare token prefix.

Terraform state and plan files are as sensitive as the tokens. Both contain
resolved zone IDs, DNS record contents and complete WAF expressions. Plan
artifacts expire after five days, and the plan summary published to the job
summary is reduced to resource addresses and actions, so no attribute values
leak into the run page.

Use reserved ranges in anything committed as an example: RFC 5737 for addresses
(`192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`) and RFC 2606 for domains
(`example.com`, `example.net`, `example.org`).

## The pipeline runs Terraform, not you

Terraform is never run against a real account or real state from a workstation,
including by contributors. No `init` against the R2 backend, no live `plan`, no
`apply`. Push a branch and let the pipeline do it. The one exception is an offline
plan in a scratch copy - no backend, a dummy token, nothing that can reach an
account - which is how a guardrail is proven (see below).

The reasons are the same ones that shaped the layer split. Credentials and state keys
stay in GitHub Environments where they can be scoped and rotated, every plan is
recorded against a commit, and the only thing that can reach a customer account is a
reviewed and approved run.

So the loop for a module or layer change is: push a branch, open a draft pull
request, read what CI says, push a fix. `ci.yml` runs on every pull request and
every push to `main`, and covers:

| Check | What it does |
|---|---|
| `terraform fmt` | Formatting, recursive |
| `tflint` | Lint, recursive, with the root `.tflint.hcl` |
| `terraform validate` | Every layer, offline. Modules are validated through the layers that call them |
| `terraform plan (offline)` | Every offline-plannable layer the change affects, against each affected account, with a dummy token |
| `config guards` | Every account var file maps to a layer, backend blocks stay commented, no state, plan or local override is tracked, and the account/layer mapping self-test |
| `API rate limiter` | The tests for `cf-api-throttle.py` |

`secret-scanning.yml` runs alongside it on the same triggers. On a push to `main`,
once every check above has passed, the `publish patch tag` job tags the commit -
see [Releases](#releases).

Seven layers can be planned without credentials: `ai_gateway`, `bulk_redirects`,
`device_posture`, `lists`, `turnstile`, `wan` and `zones`. Every other layer holds
a `data "cloudflare_*"` block and so makes a real API read at plan time: the
layers that resolve a zone by name, `account_governance` resolving role and
permission group names, `zerotrust` reading the account's existing Zero Trust
organization, and `gateway` resolving Cloudflare's category and application
catalogues. Those are covered by `validate` in CI, and planned against the live
account by `terraform-plan.yml` (dispatched by hand) and by `terraform-apply.yml`
before its approval gate. Which layers qualify is derived, not listed, so a new
layer is classified correctly without editing the workflow.

`wan` is account-scoped, resolves nothing by name and holds no data source at
all, so every guardrail in it can be fired locally with a dummy token and no
stubbing. That makes it the easiest layer in the repository to test a check
against, and there is no excuse for an untested one.

The zone-reading layers classify conservatively. Each looks up only the zones its
account tree references - a bucket's custom domain in `r2`, a zone-scoped job in
`logpush`, a published hostname in `tunnels` - so an account that references none
makes no API call at all. The `data` block is in the source either way, so the
derivation puts the layer in tier 3, and out of CI's offline plan, regardless.
That is the right direction to be wrong in.

A layer that reads the API is still testable offline, and a new guardrail in one
should be proven before review. Copy the layer to a scratch directory, keeping the
modules at the same relative path or repointing each module `source` at the real
one. Keep `terraform.tf`: it holds `required_providers`, and its backend block is
commented out, so `init` there uses a local backend. Delete the data source file,
and replace each `data.cloudflare_x.this` reference with a `local.stub_x` you
write by hand. Take the stub's shape from `terraform providers schema -json`
rather than the registry documentation, which flattens nesting modes. Plan it
against the account's committed `.tfvars` with a dummy `CLOUDFLARE_API_TOKEN`, and
every precondition in `preflight.tf` can then be made to fire on demand.

If a formatting failure is the only thing between you and green, the CI log contains
the diff.

## Test your guardrails

A validation block nobody has seen fail is a validation block that might not work.
When you add one, prove it rejects what it claims to, and do it through the pipeline.

Put a deliberately bad value in an account tree on your branch, push, and confirm the
CI plan fails with your message. This works for the seven offline-plannable layers.
For example, add an entry keyed `not_a_zone` to the `zone_config` map in
`deployment/accounts/account_a/zone_config.tfvars`, for a zone `zones.tfvars` does
not declare:

```hcl
not_a_zone = { ssl_mode = "strict" }
```

CI should fail with `zone_config has entries with no matching zone in var.zones:
not_a_zone`. If it plans cleanly, your check is doing nothing. Remove the bad value
in a follow up commit before asking for review, and say in the pull request
description which run proved the check fires, so a reviewer does not have to take it
on trust.

For guardrails on a layer that reads the API - `dns`, `waf`, `r2`, `gateway`,
`zerotrust` and the rest - CI's offline plan never runs the layer, so the same trick
works against `terraform-plan.yml` rather than `ci.yml`, or offline, with the
stubbed data source described above. A proxied TXT record in `dns.tfvars` is the
classic one:

```hcl
{ name = "@", type = "TXT", content = "v=spf1 -all", ttl = 1, proxied = true },
```

It should fail with the message about only A, AAAA and CNAME being proxiable. A
zone-reading layer whose account tree references no zone reads nothing, so most of
its guardrails can be fired with a dummy token and no stubbing at all - `r2` with
no `custom_domains`, for instance. `wan` needs neither, since it reads nothing
under any configuration.

`gateway` is the layer the stubbing recipe was worth writing down for, because
its two data sources are plain lists. Replace
`data.cloudflare_zero_trust_gateway_categories_list.this.result` with a handful
of `{ id, name, subcategories }` objects and
`data.cloudflare_zero_trust_gateway_app_types_list.this.result` with a couple of
`{ id, name }`, and every precondition in it - including the ones in
`modules/gateway`, which see only resolved IDs - can be fired against a committed
account tree with a dummy token.

## Pull requests

Branch off `main`. Keep the change to one concern: a module fix, or a layer
addition, or a customer's configuration, not all three.

In the description, say what changed and which run demonstrates it. If the change
alters a variable schema, say whether it is backwards compatible, because downstream
repositories pin a tag and someone has to decide whether they can bump it.

CI must be green. Make the `ci.yml` jobs the required status checks - `terraform
fmt`, `tflint`, `terraform validate`, `terraform plan (offline)`, `config guards`
and `API rate limiter` - plus `betterleaks & token guard` from
`secret-scanning.yml`. None of them is skipped on a pull request: the offline plan
job runs and reports "no offline-plannable layer was affected" rather than
skipping. `plan complete` is the aggregate job of `terraform-plan.yml`, which is
dispatched by hand and never runs on a pull request, so it cannot be a required
check.

### Reviewing

Has a module learned anything about layers, keys or accounts? That is the leak that
matters most, because it is the thing that stops a module being reusable.

Is each new guardrail somewhere it can actually fire, and does its message name the
input at fault? A check that reports `Invalid index` against a local has not really
been written.

Does a schema change break existing tfvars, and if so does the description say so?
Somebody downstream has to decide whether they can take the bump.

Has anything credential shaped appeared in a committed file?

Does the plan propose destroying a zone? The pipeline warns about it, but warnings
get skimmed, and that particular destroy takes every DNS record with it.

## Releases

Merging to `main` publishes a patch tag: the `publish patch tag` job in `ci.yml`
tags every green push with the next `vX.Y.Z+1`. Downstream repositories pin an
immutable tag, so a fleet upgrade is a deliberate bump rather than something that
happens because you pushed.

Module repositories published by the
[Release Manager](https://github.com/itsharryshelton/CloudflareLandingZone-Release-Manager)
tag differently: their CI reads `#major`, `#minor` or `#patch` from every commit
since the last tag and bumps by the highest one found, patch when there is none.
That is why commit messages here carry the keyword alongside their Conventional
Commits type (`fix:` `#patch`, `feat:` `#minor`, `feat!:` `#major`).

Here, minor and major bumps are decisions, not automation. Tag them by hand:

- Patch: fixes and additive changes that existing tfvars keep working across.
- Minor: new inputs or new modules, still backwards compatible.
- Major: anything that makes an existing `.tfvars` invalid. Say so in the tag
  message and give the migration.

Renaming a map key in an account tree is not a version concern, but it is
destructive. Keys are resource identity, so renaming one destroys and recreates the
resource. For a zone that means losing every DNS record in it.

## Licensing your contribution

This project is Apache License 2.0. Anything you submit is taken as offered under the
same licence, which is what section 5 of the licence says by default, so there is no
separate agreement to sign.

Two things that follow from that. Do not paste code in from a source under an
incompatible licence, GPL in particular, because Apache-2.0 cannot absorb it. And if
you add a dependency, check its licence and add it to [NOTICE](NOTICE), which lists
what this repository relies on and under what terms.

There are no per file SPDX headers. The licence lives in `LICENSE` and applies to the
repository. If you would rather have headers, that is a reasonable change, but do it
in one pass across every file rather than adding them piecemeal.