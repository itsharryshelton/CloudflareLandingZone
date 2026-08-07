# Cloudflare Landing Zones (CFLZ)

Enterprise-grade Infrastructure-as-Code (IaC) for managing multi-account, multi-zone Cloudflare footprints through a single set of standardised modules.

New here? Go to the Wiki for the Guides.

## Why a landing zone

A Landing Zone is the agreed baseline an enterprise environment lands in before any workload arrives. Identity, network topologies, security posture, naming conventions, and guardrails are decided once and enforced universally. Without one, every environment becomes an ad-hoc build, creating configuration drift and audit blind spots.

Azure Landing Zones (ALZ) established this standard for cloud adoption. CFLZ applies the exact same enterprise architectural rigour to Cloudflare.

### The Core Principles

- GitOps Over "Click-Ops"
- Declarative State & Drift Detection
- Separation of Logic & Configuration

<img width="2063" height="3381" alt="CFLZ" src="https://images.harryshelton.com/CFLZ.png" />

## Architectural Framework

CFLZ mirrors the Microsoft Cloud Adoption Framework (CAF) hierarchy, adapting it to the Cloudflare edge ecosystem.

### Platform Landing Zone (Account & Enterprise Governance)

The Platform Landing Zone establishes your organisation's primary Cloudflare edge foundation. It defines how you structure your Cloudflare Accounts, enforce global security governance, and deliver shared edge capabilities centrally. Most organisations maintain one primary Platform Landing Zone per main Enterprise Account or administrative scope.

A Platform Landing Zone consists of account-level governance configurations and centralised infrastructure services. A core function of the platform layer is providing a standardised, automated mechanism to vend zone-level Application Landing Zones to development and workload teams.

- Establishes the overarching administrative structure across your Cloudflare footprint. It organises account-level RBAC roles, audit logging, and global security policies (such as baseline WAF rulesets, Account-level Rate Limiting, API Shield schemas, and Zero Trust identity policies). This layer separates platform-wide policy from individual domain configurations, applying governance consistently without creating administrative overhead.
- Shared capabilities provisioned centrally for all domains and workloads. Common examples include central Logpush streams (exporting to Azure Sentinel, SIEM, or R2 buckets), unified Identity Provider integration (e.g., Microsoft Entra ID), global Anycast DNS routing, and enterprise mTLS configurations. Only centralise capabilities that provide clear security, operational, or economic benefits across multiple workloads.
- Providing a repeatable, automated process for requesting, building, and vending Application Landing Zones (Domains/Zones) to workload teams. Driven by Infrastructure-as-Code (Terraform & GitOps), this vending process guarantees that every newly onboarded domain automatically inherits your organisation's security and compliance baselines.

### Application Landing Zone (Zone & Workload Level)

Each web application, microservice, or domain operates inside a dedicated Application Landing Zone. It encapsulates all Cloudflare resources owned and operated by specific workload teams across development, staging, and production environments.

- Manages zone DNS records, custom WAF rules, Cloudflare Workers/Pages, R2 buckets, and Load Balancers.
- Assigns zones to specific environment templates (e.g., Public Web App, Internal/Corp Zero Trust, or Edge Compute Worker), allowing teams domain autonomy while inheriting global platform guardrails.

### Repository Structure

CFLZ abstracts infrastructure logic away from customer data, allowing onboarding or DNS modifications to occur strictly as configuration edits.

```text
├── modules/                   # Agnostic building blocks (flat arguments, real IDs)
├── deployment/
│   ├── layers/                # Fleet-shaped orchestrators calling baseline modules
│   └── accounts/              # Customer & account configuration (.tfvars live here)
```

- modules/: Agnostic, reusable modules that know nothing about specific accounts or API keys.
- deployment/layers/: Top-level orchestration layers that compose modules into complete environments.
- deployment/accounts/: The only directory operators edit. Contains .tfvars per Cloudflare account.

## Built-in Guardrails & Pre-flight Checks

CFLZ prioritises fail-safe operations. Instead of failing halfway through a live apply, invalid or dangerous configurations fail during the plan phase via native HCL validation and precondition blocks.

### Safety Guardrails
- Super Administrator Lockout Prevention: The account_governance layer refuses to assign the Super Administrator role (by name or ID) unless explicitly unlocked in code, protecting the root access model.
- WAF Admin Lockout: Selecting block_admin_from_untrusted without providing a trusted IP list will immediately fail execution, preventing self-lockout.
- Zero Trust Bypass Restrictions: Access policies configured with decision = "bypass" are rejected by default to prevent accidental exposure of protected endpoints.
- Team Domain Protection: Renaming a Zero Trust Team domain requires explicit confirmation flags, preventing broken Access URLs and forced WARP client re-enrolments.
- Billing Change Visibility: Terraform never alters a zone's rate plan unless subscription management is explicitly enabled, and any run that would do so prints a warning naming every zone and the plan it moves to. An accidental downgrade strips WAF, rate limiting and Bot Management entitlements from a live zone.
- R2 Public Exposure Control: A bucket asking for its anonymous `r2.dev` URL, or a CORS rule allowing every origin, fails the plan naming the bucket. Both are one dashboard click away and both make object data readable from any visitor's browser.
- R2 Irreversible Deletion Guard: A lifecycle rule that expires objects across an entire bucket needs an explicit unlock, because R2 has no versioning and nothing deleted comes back. A lifecycle deletion that collides with an object lock rule fails the plan too - Cloudflare accepts that pair and then refuses the deletion silently, forever.
- Cloudflare WAN Blackhole Prevention: A static route's next hop is derived from the tunnel rather than typed. A tunnel is numbered from a /31 and the address you configure is Cloudflare's end, so a hand-written next hop one address out is accepted by the API, displayed as healthy, and silently discards the traffic. A prefix reachable over only one tunnel, a tunnel with health checks disabled, and a `0.0.0.0/0` route each fail the plan too - the first two remove the failover the second tunnel was bought for, and the third attracts every destination nobody thought about.
- Cloudflare WAN Secret Handling: IPsec pre-shared keys are a `sensitive` variable supplied from the pipeline environment and are never declared in a committed `.tfvars`. A key naming a tunnel that does not exist fails the plan, so a rotation that misses cannot leave a tunnel quietly running on a key nobody holds.

### Configuration Correctness Checks
- DNS Validation: Catches record collisions, proxied TXT records, or proxied records with explicit TTLs before submission.
- Load Balancer Logic: Verifies pool health-check timeouts are shorter than intervals, and ensures minimum healthy origin counts do not exceed pool capacity.
- Identity Integrity: Validates that user groups do not assign permissions to undeclared members.
- Plan Tier Gating: Each zone declares its Cloudflare tier, and a bot management setting the tier cannot support fails the plan naming the field and the plan it needs, rather than failing part-way through an apply on a Cloudflare error that names neither.
- Bot Rule Placement: Per-category bot rules are emitted into the single ruleset Cloudflare permits per phase per zone, ahead of the baseline and tenant rules, so an allow can take effect without a second ruleset silently fighting the first.

## Deployment & Multi-Tenant Model
While the repository supports standalone deployments out of the box, enterprise environments should follow two core architectural patterns:

### 1. Isolated Per-Customer Repositories
Do not run multiple customers inside a single repository directory. Managing multiple clients under one repo shares pipeline permissions and state keys, exposing all clients to a single operator error.

> Best Practice: Copy or fork this repository into the customer’s own isolated estate (their GitHub Org, their R2 state bucket, their scoped API tokens).

### 2. Externalised Versioned Modules
While modules/ sits inside this repository for development convenience for this template repo: production environments should reference tagged, external module repositories:

```hcl
module "zone_base" {
  source = "git::https://github.com/<your-org>/cloudflare-lz-modules.git//modules/zone_base?ref=v1.4.0"
}
```
This guarantees that changes on main do not automatically alter live infrastructure until a customer explicitly bumps their module version.


## CI/CD Pipeline & State Management

CFLZ uses GitHub Actions driven strictly by GitOps workflows. Terraform is executed only inside the pipeline—never on local developer workstations.

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

> ## A Note on Feature Coverage & Maintenance
> This project is designed to give you a solid, enterprise-ready starting point for deploying Cloudflare Landing Zones, but it doesn't cover every single Cloudflare feature out of the box. You may find that your specific deployment requires tweaking the `.tf` files to add new variables or support additional resources.  
> 
> While core capabilities are tested, I can't test every edge case or keep up with every provider update instantly. If you hit a gap, find a bug, or want to add a feature, please check out [`CONTRIBUTING.md`](CONTRIBUTING.md) and submit a Pull Request!
> At a minimum, before I commit I've formatted & validated terraform formatting and run offline tests against the guardrails; and tested the deployment where I'm able to. I do not have a timeline for features, I add when I have the time or think needs adding next; any requests please submit.

## Licence

Distributed under the Apache License 2.0 - See [LICENSE](LICENSE) and [NOTICE](NOTICE).

### Open-Source & BSL Considerations
- Apache-2.0 License: You are free to copy, modify, and run this code for commercial clients privately without triggering file-level copyleft obligations (unlike MPL-2.0).
- Terraform BSL / OpenTofu: Terraform (v1.6+) is licensed under the Business Source License (BSL 1.1) by IBM. CFLZ relies on standard HCL features and is fully compatible with OpenTofu (MPL-2.0) if your organization requires a completely open-source toolchain.
