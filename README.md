# Cloudflare Landing Zones (CFLZ)

Enterprise-grade Infrastructure-as-Code (IaC) for managing multi-account, multi-zone Cloudflare footprints through a single set of standardised modules.

New here? Go to the Wiki for the Guides.

Looking to quickly setup the code/repos in your Github? Check out my [Release Manager](https://github.com/itsharryshelton/CloudflareLandingZone-Release-Manager)

## Why a landing zone

A Landing Zone is the agreed baseline an enterprise environment lands in before any workload arrives. Identity, network topologies, security posture, naming conventions, and guardrails are decided once and enforced universally. Without one, every environment becomes an ad-hoc build, creating configuration drift and audit blind spots.

Azure Landing Zones (ALZ) established this standard for cloud adoption. CFLZ applies the exact same enterprise architectural rigour to Cloudflare.

### The Core Principles

- GitOps Over "Click-Ops"
- Declarative State & Drift Detection
- Separation of Logic & Configuration

<img width="2063" height="3381" alt="CFLZ" src="https://images.harryshelton.com/CFLZ.png" />

## Architectural Framework

CFLZ is designed to be similar to the Microsoft Cloud Adoption Framework (CAF), adapting it to the Cloudflare edge ecosystem, because it is a tried and tested method, but also allows Azure Architects to quickly understand and adopt a Cloudflare Landing Zone's Structure.

### Platform Landing Zone (Account Governance)

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

## Decoupled Layer Architecture & Blast Radius Containment

Monolithic Terraform states create catastrophic blast radius vulnerabilities within enterprise edge environments. CFLZ resolves this by decomposing infrastructure into discrete, decoupled layers - each managing independent state files, dedicated pipeline tokens, and distinct operational lifecycles.

```text
Platform Layer (Central Governance)
├── account_governance   (RBAC, user groups, audit configuration)
├── zerotrust            (Access applications, service tokens, IdPs)
├── device_posture       (Device posture checks, MDM and EDR integrations such as Intune and CrowdStrike)
├── tunnels              (Cloudflare Tunnels, public hostnames, private network routes)
├── gateway              (SWG egress filtering: DNS, network, and HTTP)
├── logpush              (Log streams: audit, Gateway and zone logs to a SIEM or R2 - Enterprise)
└── wan                  (Magic WAN tunnels, interconnects, static routes)

Application Layer (Zone & Workload Scope)
├── zones                (Zone lifecycle, DNS records, vanity nameservers)
│   ├── waf              (Firewall rulesets, rate limiting, bot policies)
│   ├── load_balancing   (Health monitors, origin pools, failover logic)
│   └── r2               (Bucket policies, CORS, custom domains)
```

### Architectural Principles

- **Independent State Segmentation:** An apply failure, configuration drift, or state corruption within a high-velocity layer (such as `waf` or `r2`) can never compromise foundational DNS zones or account-level routing. Zone deletion - the most destructive failure mode in Cloudflare - is architecturally isolated to the `zones` layer alone.
- **Least-Privilege Scoped Credentials:** Each pipeline runner operates under an API token restricted strictly to its layer domain. The `waf` runner holds `Zone WAF:Edit` and `Zone:Read`, preventing it from altering DNS or modifying account RBAC. Only `account_governance` is granted identity management privileges, ensuring complete separation between edge traffic rules and administrative access.
- **Dynamic Plan-Time Discovery:** Layers do not consume `terraform_remote_state` outputs. Instead, workload layers resolve parent zone metadata dynamically via native data source filters at plan time. This eliminates rigid pipeline locking, enabling concurrent execution and independent layer migrations without inter-state coupling.
- **Targeted Blast Containment:** Security controls, routing configurations, and identity policies can be reviewed, tested, and promoted independently, aligning Cloudflare operations with enterprise Zero Trust and Microsoft Cloud Adoption Framework (CAF) governance principles.


## Deployment & Multi-Tenant Model

While the repository supports standalone deployments out of the box, enterprise environments should follow two core architectural patterns:

### 1. Isolated Per-Customer Repositories

Do not run multiple customers inside a single repository directory. Managing multiple clients under one repo shares pipeline permissions and state keys, exposing all clients to a single operator error.

> [!TIP]
> **Best Practice:** Copy or fork this repository into the customer’s own isolated estate (their GitHub Organisation, their R2 state bucket, their scoped API tokens) using the [Release Manager](https://github.com/itsharryshelton/CloudflareLandingZone-Release-Manager).

### 2. Externalised Versioned Modules

While `modules/` sits inside this repository for development convenience in this upstream template, production environments should reference tagged, external module repositories:

```hcl
module "dns" {
  source = "git::https://github.com/your-org/terraform-cloudflare-lz-dns.git?ref=v1.2.0"
}
```

This guarantees that changes on `main` do not automatically alter live infrastructure until a customer explicitly bumps their module version in their deployment layer.

## Architectural Decisions: CFLZ vs Cloudflare Guidance

Cloudflare's official Terraform best practices recommend organising configurations strictly by **Account > Zone > Product** (e.g., `account_a/zone_a/dns/`) and explicitly advise operators to *"Avoid modules (or use them sparingly)"*. While adequate for simple setups with a handful of domains, that layout collapses under enterprise and MSP operational demands. CFLZ deliberately takes an alternative architectural route.

### 1. Resolving Cloudflare's "Avoid Modules" Dilemma

Cloudflare’s official documentation warns against modules primarily because teams often create monolithic, polymorphic abstractions that hide critical security and network behaviours behind complex ternary operators and unpinned local paths. When a shared monolithic module changes internally, dependent resources can be unexpectedly altered or recreated.

CFLZ's production model-using dedicated repositories with isolated scopes and immutable SemVer tags-directly resolves Cloudflare's critique:

- **Interface Stability:** Breaking changes to a module (such as modifying required inputs or altering resource addressing that triggers recreation) cannot reach target customer environments without an explicit, intentional tag bump in the layer's `.tf` file.
- **Independent Lifecycle:** An update to `terraform-cloudflare-lz-waf` does not alter the checksum or state lifecycle of `terraform-cloudflare-lz-dns`.
- **Auditability:** Dedicated repositories allow fine-grained commit histories and vulnerability tracking per Cloudflare product area, aligning directly with enterprise change management and ISO/SOC2 audit standards.

> [!IMPORTANT]
> **Enforce GitHub Tag Protection & Commit-Pinned Sources:** In a production implementation (as opposed to this upstream template repository), each module should reside in its own dedicated repository. Operators must configure **GitHub Tag Protection Rules** on module repositories to guarantee that release tags cannot be overwritten or deleted. For maximum immutability, layers should reference tagged releases or commit SHAs.

### 2. Fleet Orchestration vs Zone Directory Duplication

Cloudflare's recommended structure treats each zone as a filesystem directory containing duplicate `.tf` files. For an enterprise or MSP managing 50+ zones across multiple accounts, this leads to hundreds of redundant files: bumping a provider version or adjusting a baseline setting requires edits across dozens of directories.

CFLZ inverts this relationship:
- **Product Layers as Root Orchestrators:** Code lives once under `deployment/layers/<product>/`.
- **Zones as Data Declarations:** Zones are managed as entries (`for_each` maps) inside `deployment/accounts/<account>/*.tfvars`.
- **Targeted Operations Without Monoliths:** Unlike monolithic workspaces, layers can be targeted individually in CI/CD pipelines (`tf-matrix.sh`), ensuring fast execution, discrete plans, and an isolated blast radius per product.



## CI/CD Pipeline & State Management

CFLZ uses GitHub Actions driven strictly by GitOps workflows. Terraform is executed exclusively inside the pipeline - never on local developer workstations.

| Workflow                                                       | Trigger                          | Touches Cloudflare? | Can change anything?              |
| ----------------------------------------------------------------| ----------------------------------| ---------------------| -----------------------------------|
| [`ci.yml`](.github/workflows/ci.yml)                           | Every PR, every push to `main`   | No                  | No (offline validation & linting) |
| [`secret-scanning.yml`](.github/workflows/secret-scanning.yml) | Every PR, push to `main`, manual | No                  | No                                |
| [`terraform-plan.yml`](.github/workflows/terraform-plan.yml)   | Manual dispatch only             | Reads               | No                                |
| [`terraform-apply.yml`](.github/workflows/terraform-apply.yml) | Manual dispatch only             | Reads & writes      | Yes, after human approval         |
| [`state-forget.yml`](.github/workflows/state-forget.yml)       | Manual dispatch only             | No                  | State only, after approval        |
| [`state-unlock.yml`](.github/workflows/state-unlock.yml)       | Manual dispatch only             | No                  | State lock only, after approval   |
| [`_terraform-run.yml`](.github/workflows/_terraform-run.yml)   | Reusable (called by plan/apply)  | Per caller mode     | Controlled by caller              |

### Operational Governance & Safety Guardrails

- **Apply Never Runs Without an Approved Plan:** `terraform-apply.yml` has no automated `push` trigger. Merging code to `main` never applies changes to live infrastructure automatically. When ready, operators trigger the apply workflow manually. It plans first, publishes the plan artifact, halts for designated human reviewer approval within the target GitHub Environment, and then applies that exact, immutable plan file. There is no `-auto-approve` flag and no destroy path anywhere in the platform.
- **Automated Secret Scanning (`secret-scanning.yml`):** Runs on every pull request, push to `main`, and manual dispatch. It enforces automated credential leak detection (via `betterleaks`) to guarantee that sensitive credentials-such as Cloudflare API tokens, Entra ID client secrets, or R2 access keys - are never committed to version control.
- **Zero-Downtime State Refactoring (`state-forget.yml`):** A maintenance workflow that instructs Terraform to forget a resource without deleting it at Cloudflare (`terraform state rm`). This facilitates moving resources between layers (for example, handing DNS records from the `zones` layer over to the dedicated `dns` layer) without edge disruption, gated by explicit human approval.
- **Distributed State Lock Recovery (`state-unlock.yml`):** Safely releases abandoned S3 conditional lockfiles in Cloudflare R2 left behind by cancelled or interrupted pipeline jobs, resolving `PreconditionFailed` deadlocks without requiring manual R2 bucket intervention.
- **R2 State Backend with Native Locking:** Terraform state resides in Cloudflare R2 via the S3-compatible backend (`use_lockfile = true`), partitioned with one independent state key per account and layer. Native S3 conditional writes enforce distributed locking without requiring external lock tables (such as DynamoDB).
- **Proactive API Rate Limiting:** The provider's requests are paced through a loopback HTTP rate limiter ([`cf-api-throttle.py`](.github/scripts/cf-api-throttle.py)) running inside the runner container. This prevents plan and apply runs against dense zones from breaching Cloudflare's threshold of 1,200 requests per 5 minutes per credential (HTTP 429).
- **Least-Privilege Environment Scoping:** API tokens, backend R2 keys, and environment variables are strictly isolated across per-layer GitHub Environments (`<account>-<layer>-plan` and `<account>-<layer>-apply`), ensuring credentials cannot leak across tenant boundaries or administrative domains.



## Documentation

| Document | For |
|---|---|
| [GETTING_STARTED.md](GETTING_STARTED.md) | Making a change through the pipeline, common tasks, and what the error messages mean |
| [VARIABLES_AND_SECRETS.md](VARIABLES_AND_SECRETS.md) | Quick reference: every GitHub variable, secret and environment to set, per layer |
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
