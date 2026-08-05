# Cloudflare Landing Zones (CFLZ)

Terraform for managing Cloudflare at enterprise scale: many accounts, many zones, one set of reviewed modules.

New here? Go to [GETTING_STARTED.md](GETTING_STARTED.md).

## Why a landing zone

A landing zone is a cloud adoption term. It is the agreed baseline an environment
lands in before any workload arrives: identity, network, security posture, naming and
guardrails decided once and applied the same way everywhere. The alternative is every
environment being a one off, built by whoever was on shift, and nobody being able to
say what is configured where.

Azure Landing Zones (ALZ) is the pattern most enterprises have met. This repository
applies the same idea to Cloudflare, and borrows the naming on purpose: Cloudflare
Landing Zones, or CFLZ. If you have worked with ALZ, the shape here should be
familiar. A reviewed set of modules, a baseline every account gets, and per account
configuration that sits apart from the logic.

## Why code and state

Terraform state is a record of what actually exists. That gives three things a
collection of change requests cannot. A plan shows the exact change before it
happens, so a reviewer approves a diff rather than an intention. Drift is detectable,
because anything changed outside the pipeline shows up as a difference on the next
plan. And history is real: `git log` explains why a setting is the way it is, and who
approved it.

## Why not the dashboard

Cloudflare is an API first company and the dashboard is a client of that API, so
scripting against it directly works fine. What API calls do not give you is intent
recorded somewhere reviewable, a diff before the change, or a source of truth for
current configuration. Every change is fire and forget, and the only record is
whatever the operator wrote in the ticket.

Terraform is the enterprise standard for this, the Cloudflare provider is first
party, and auditors and new engineers can both read it. The dashboard stays useful for
reading state and for analytics. It is not where changes get made.

## What this is

A template repository that separates infrastructure logic from customer
configuration, so that onboarding a customer or changing their DNS is a
configuration edit rather than a code change.

The modules under [modules/](modules/) are agnostic building blocks. They take flat
arguments and real IDs, and know nothing about accounts, keys or profiles. The
layers under [deployment/layers/](deployment/layers/) own the fleet shaped view and
call those modules. Configuration lives in
[deployment/accounts/](deployment/accounts/), one directory per Cloudflare account,
and it is the only thing an operator edits.

This repository is the upstream. It gets copied to a per customer repository where
operators change `.tfvars` files. Module and layer changes happen here and reach
customers as a version bump.

## Setup

Two recommendations for anyone standing this up properly. Neither is enforced by the
code, and the repository works without them, but they are the shape it was designed
for.

**One deployment per customer.** The account split under
[deployment/accounts/](deployment/accounts/) exists so that a single customer with more
than one Cloudflare account can be managed in one place. It is not a way to hold
several customers side by side. Doing that puts every customer's configuration behind
one set of repository permissions and one pipeline, so an operator with access to one
customer has access to all of them, and a mistake in a shared layer reaches everyone at
once. Ideally the deployment lives in the customer's own estate: their GitHub
organisation, their R2 bucket for state, their API tokens. Credentials then only ever
grant access to the account they belong to.

**Modules in their own repository.** [modules/](modules/) currently sits alongside the
deployment in this repository, which is convenient while both are moving. 

At best practice, the modules are their own repository, tagged, and referenced by URL:

```hcl
module "zone_base" {
  source = "git::https://github.com/<org>/cloudflare-lz-modules.git//modules/zone_base?ref=v1.4.0"
}
```

That gives each customer an explicit module version rather than whatever happened to be
on `main` when they last pulled, and lets a module change be tested once and rolled out
per customer on their own timetable.

Bad configuration fails at plan time with a message naming the offending input,
rather than halfway through an apply. Single field checks live in `variables.tf` as
validation blocks. Cross field and cross item checks live in preconditions, in
`main.tf` for modules and `preflight.tf` for layers.

A few examples of what gets caught: a proxied record with an explicit TTL, a proxied
TXT record, two DNS records that collide once names are qualified, a `zone_key`
pointing at nothing, a load balancer hostname outside its zone, a pool whose minimum
healthy origin count exceeds its origin count, and a health check timeout longer
than its interval.

One is worth calling out because it is a safety property rather than a
correctness one. The WAF baseline rules are parameterised, and selecting
`block_admin_from_untrusted` with an empty trusted IP list would render as "block
admin access from everywhere", including from you. The plan fails instead.

## Pipeline

GitHub Actions. See [.github/workflows/README.md](.github/workflows/README.md) for
the environments, secrets and token scopes.

| Workflow | Trigger | Touches Cloudflare |
|---|---|---|
| `ci.yml` | every pull request and push | no |
| `terraform-plan.yml` | pull requests touching Terraform, manual | reads |
| `terraform-apply.yml` | push to `main`, manual | reads and writes, after approval |

Apply always consumes a plan file produced earlier in the same run, so the change a
reviewer approved is the change that executes. There is no `-auto-approve` anywhere,
and no destroy path.

State lives in Cloudflare R2 through the S3 compatible backend, one key per account
per layer.

Terraform runs in the pipeline and nowhere else. Not on an operator's machine, and not
on a contributor's either. Credentials and state keys stay in GitHub Environments,
where they are scoped per account and per layer and can be rotated in one place. A
change reaches a customer by pull request, plan, review and approval, so there is
always a recorded plan behind it.

## Documentation

| Document | For |
|---|---|
| [GETTING_STARTED.md](GETTING_STARTED.md) | Making a change through the pipeline, common tasks, and what the error messages mean |
| [deployment/README.md](deployment/README.md) | How layers and accounts fit together |
| [.github/workflows/README.md](.github/workflows/README.md) | Pipeline, environments, token scopes, security notes |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Changing the Terraform rather than the configuration |

A module documents itself. Its inputs, defaults and guardrails live in the
`description` and `validation` blocks in its own `variables.tf`, and the reasoning
lives in the header comments of `locals.tf` and `main.tf`. There are no separate
module READMEs to drift out of date.

## Licence

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

Copy it, modify it, run it for customers, keep your changes private. Apache-2.0 asks
you to keep the licence and notice, state what you changed, and it grants patent
rights explicitly. It was chosen over MPL-2.0 for that reason: this repository is
meant to be copied into a per customer repository and edited there, and MPL-2.0's
file level copyleft would oblige whoever did that to publish their edits.

One thing to be aware of if you adopt this. The code here is Apache-2.0, but Terraform
itself is not open source from version 1.6 onward. It moved to the Business Source
License 1.1, now with IBM as licensor. That is a licence for the tool you run, not for
this repository, and it does restrict using Terraform to build a competing product.
Check it against your own use if you sell services built on this.
[OpenTofu](https://opentofu.org/) is the MPL-2.0 fork if that matters to you, and
nothing here depends on Terraform-only behaviour, though the pipeline pins Terraform
and has not been tested against OpenTofu.