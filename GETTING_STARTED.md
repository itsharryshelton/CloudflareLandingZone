# Getting started

You will not run Terraform. You edit a configuration file, open a pull request, read
the plan the pipeline posts back, and approve the apply.

That is deliberate. Nobody holds a Cloudflare token or a state key on a laptop, every
change is reviewed against a real plan before it happens, and the thing that gets
applied is the exact plan somebody approved.

Jump to a task: 

[add or change a DNS record](#task-add-or-change-a-dns-record),

[add a zone](#task-add-a-zone), [add a WAF rule](#task-add-a-waf-rule),

[onboard a customer account](#task-onboard-a-customer-account).

If something fails, see [when it goes wrong](#when-it-goes-wrong) before changing
anything. Most failures are guardrails firing on purpose, and the message says what
to fix.

## How a change reaches Cloudflare

```
edit a .tfvars file
        |
   open a pull request
        |
   CI checks + a plan, posted as a PR comment      <- nothing has changed yet
        |
   review and merge
        |
   apply runs, and pauses for approval             <- last chance to stop
        |
   you approve, Terraform applies that exact plan
```

Five things worth knowing about that loop.

A plan is free and reversible. It reads your Cloudflare account and reports what
would change. Nothing happens to a customer until somebody approves an apply.

The apply consumes the plan file from earlier in the same run. There is no
`-auto-approve` anywhere in the repository, and if state moved between the plan and
your approval, Terraform rejects the plan as stale rather than doing something you
did not review.

Only affected work runs. Change `accounts/account_a/waf.tfvars` and only the `waf`
layer for `account_a` is planned. Change a module and every layer that calls it is
planned, for every account.

`zones` goes first, then `waf` and `load_balancing`. The apply workflow handles that
ordering for you.

There is no destroy button. Removing a zone from configuration will show up as a
destroy in a plan, and you should treat that with suspicion, because it takes every
DNS record in that zone with it.

## What you need

Write access to this repository, and a browser.

You do not need Terraform installed. You do not need a Cloudflare API token. You do
not need the R2 state credentials. Those live in GitHub Environments and only the
pipeline can reach them.

A local checkout and an editor are convenient for anything more than a one line
change, but the GitHub web editor is fine for a DNS record.

## Where things live

You only ever edit files under `deployment/accounts/`.

```
deployment/accounts/account_a/
├── account.tfvars              the Cloudflare account ID
├── zones.tfvars                which zones exist: key -> domain name
├── dns.tfvars                  zone settings and DNS records
├── waf.tfvars                  firewall and rate limiting policies
├── load_balancing.tfvars       load balancers, pools, health checks
└── account_governance.tfvars   who can sign in to the account, and with what
```

Everything under `deployment/layers/` and `modules/` is the engine. If you find
yourself editing a `.tf` file to configure a customer, stop, because that change
belongs upstream. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Your first change, start to finish

A worked example: adding a `docs` CNAME to `account_a`.

### 1. Branch and edit

```bash
git checkout -b add-docs-record
```

Open `deployment/accounts/account_a/dns.tfvars`, find the zone key under
`zone_config`, and add a record to its list:

```hcl
zone_config = {
  primary = {
    dns_records = [
      { name = "@", type = "A", content = "203.0.113.10", ttl = 1, proxied = true },
      { name = "docs", type = "CNAME", content = "example.com", ttl = 1, proxied = true },
    ]
  }
}
```

Commit and push.

### 2. Open a pull request

Two workflows start on their own.

`CI` runs formatting, linting, validation and the configuration guards. It touches
no Cloudflare account. If this fails, the problem is in the file you edited and the
log will name it.

`Terraform Plan` works out which account and layer your change affects, plans it
against the real account with a read-only token, and posts a comment on the pull
request.

### 3. Read the plan comment

It looks roughly like this:

```
#### Terraform plan - `account_a` / `zones`

`add=1 change=0 destroy=0`

- `create` module.zones["primary"].cloudflare_dns_record.this["CNAME/docs.example.com/example.com"]
```

Check three things. Is the count what you expected, in this case one create? Is
`destroy=0`? And is the resource address the thing you meant to touch?

The comment deliberately lists addresses and actions only, with no attribute values,
because anyone with read access to the repository can see a PR comment. The full plan
is attached to the workflow run as an artifact and expires after five days.

### 4. Merge

Get a review and merge. The required status check is `plan complete`, not `plan`,
because `plan` is legitimately skipped when a change affects no account.

### 5. Approve the apply

Merging to `main` starts `Terraform Apply`. It plans again, then waits, showing
something like `apply (tier 1)` pending review.

Open the run, read the plan summary in the job output, and approve. Terraform then
applies that plan file. You are approving a specific change to a specific account
and layer, which is why there is one environment per account per layer.

If the plan on that run is not what the PR showed you, do not approve. Something
changed underneath, either in Cloudflare directly or in another run.

## Task: add or change a DNS record

Edit `deployment/accounts/<account>/dns.tfvars` under the right zone key, then open a
pull request.

Four rules catch most mistakes:

Proxied records need `ttl = 1`, which means automatic. Cloudflare rejects a real TTL
on a proxied record.

Only A, AAAA and CNAME can be proxied. Everything else needs `proxied = false`.

Names are qualified for you, so `docs`, `docs.example.com` and `DOCS.Example.Com.`
are the same record. Declaring two of them fails the plan rather than quietly
creating one.

MX, SRV and URI records need a `priority`.

## Task: add a zone

Two files, because identity is kept apart from configuration. Every layer needs to
know that `shop` means `example.net`; only the `zones` layer needs to know what
records it has.

First `zones.tfvars`:

```hcl
zones = {
  primary = { domain_name = "example.com" }
  shop    = { domain_name = "example.net" }
}
```

Then `dns.tfvars`:

```hcl
zone_config = {
  shop = {
    dns_records = [
      { name = "@", type = "A", content = "203.0.113.20", ttl = 1, proxied = true },
    ]
  }
}
```

The key, `shop` here, is permanent. Renaming it later destroys the zone and recreates
it, taking every DNS record with it. Keys are scoped to their account, so
`account_a`'s `primary` and `account_b`'s `primary` are unrelated.

### Use two pull requests if the zone also needs WAF or a load balancer

The `waf` and `load_balancing` layers find a zone by looking its domain name up
through the Cloudflare API. Before the zone exists there is nothing to find, so a
pull request that adds a zone *and* its WAF policy will fail the `waf` plan and you
will not be able to merge it.

Split it:

1. First pull request adds the zone. Merge and approve the apply.
2. Second pull request adds the WAF or load balancer configuration. Its plan now
   resolves the zone and succeeds.

The apply workflow itself is not the problem here. It plans tier 2 only after tier 1
has applied, so if both changes ever do land on `main` together it still works. It is
the pull request plan that cannot succeed early, and that is the check standing
between you and a merge.

### Then delegate at your registrar

A new zone sits in `pending` until the domain's registrar points at Cloudflare's
nameservers. Nothing serves traffic until you do this, and it is the usual reason an
apply succeeds but the site does not work.

After the apply, get the assigned nameservers from the Cloudflare dashboard, on the
zone's Overview page. Set them at the registrar. The zone goes `active` within
minutes to hours.

Until it does, expect `waf` and `load_balancing` plans for that zone to fail on the
lookup.

## Task: add a WAF rule

Most of the time you do not write a rule, you pick one by name from the platform
catalogue.

Edit `deployment/accounts/<account>/waf.tfvars`:

```hcl
waf_trusted_ip_ranges = ["203.0.113.0/24"]

waf_policies = {
  primary = {
    zone_key              = "primary"
    baseline_custom_rules = ["block_admin_from_untrusted", "block_known_exploit_paths"]
    baseline_rate_limits  = ["auth_brute_force"]
  }
}
```

What is available:

| Rule | What it does | Needs |
|---|---|---|
| `block_admin_from_untrusted` | Blocks admin paths from outside your trusted ranges | `waf_trusted_ip_ranges` |
| `geoblock_countries` | Blocks listed countries | `waf_blocked_countries` |
| `block_known_exploit_paths` | Blocks probes for `.env`, `.git` and similar | nothing |
| `challenge_undisclosed_bots` | Managed challenge for suspicious automation | `waf_trusted_ip_ranges` |
| `log_trusted_admin_access` | Logs admin access from trusted ranges | `waf_trusted_ip_ranges` |
| `auth_brute_force` | 20 requests a minute per IP on login paths | nothing |
| `api_general` | 600 requests a minute per IP under `/api/` | nothing |
| `origin_error_shield` | Backs off when the origin returns 5xx | nothing |
| `observe_only` | Logs rates without enforcing, for sizing a limit | nothing |

If a rule needs a list and you leave that list empty, the plan fails. That is not
pedantry. `block_admin_from_untrusted` with no trusted ranges means "block admin
access from everywhere", including from you.

Baseline rules always evaluate before anything you add yourself, so your own rule
cannot let through something the baseline blocks.

For genuinely bespoke logic, write the expression:

```hcl
custom_block_rules = [
  {
    name        = "Block legacy XML-RPC endpoint"
    expression  = "http.request.uri.path eq \"/xmlrpc.php\""
    action      = "block"
    description = "Unused here and heavily probed."
  },
]
```

`skip` is not an available action. It needs parameters this repository does not model
yet, so offering it would produce plans that fail on apply.

New to Cloudflare expressions? Build and test one in the dashboard under Security,
then Rules, and paste the expression here rather than writing it blind.

## Task: give somebody access to the Cloudflare dashboard

Edit `deployment/accounts/<account>/account_governance.tfvars`. Two things happen
there: people are invited, and permissions are handed out through named groups.

Read a plan from this file more carefully than any other. It is the one that grants
and revokes real people's access, and deleting an entry locks that person out on the
next apply.

Add the person, then put them in the group that carries the permissions they need:

```hcl
account_members = {
  new_starter = {
    email = "new.starter@example.com"
    # No role_names, so they get the platform default: enough to sign in and
    # nothing else. The real permissions come from the group below.
  }
}

user_groups = {
  dns_operators = {
    name        = "DNS Operators"
    member_keys = ["new_starter"]
    policies = [
      { permission_group_names = ["DNS Write", "Zone Read"] },
    ]
  }
}
```

Names, not IDs. Roles and permission groups are named exactly as the dashboard shows
them under Manage Account, then Members. Get one wrong and the plan fails listing
what the account actually has, which is usually faster than hunting for the right
wording in the dashboard.

They will not be able to sign in until they accept the invitation Cloudflare emails
them. Until then the `member_statuses` output says `pending`, and that is the first
thing to check when access has apparently been granted but nothing works.

Three things the plan will refuse:

- **Super Administrator.** Restricted by default, whether asked for by name or by
  ID, because it is the one role that can rewrite the account's own access model.
  Granting it means editing `restricted_role_names` in
  `deployment/layers/account_governance/defaults.auto.tfvars` on a pull request that
  says why.
- **An address outside the permitted domains**, if `allowed_email_domains` is set for
  this deployment.
- **A `member_keys` entry that matches no member**, which would otherwise leave
  somebody signed in and staring at an empty dashboard.

To remove somebody, delete their `account_members` entry and any `member_keys`
mentioning them. Expect the plan to show a destroy, and check it is only theirs.

## Task: onboard a customer account

Part of this is configuration and part of it is administration, so expect to need
somebody with repository admin rights.

Configuration, in a pull request:

1. Create `deployment/accounts/<name>/` and copy the six files from `account_a`.
2. Put the real Cloudflare account ID in `account.tfvars`. It is the 32 character hex
   string in the dashboard URL, and also on any zone's Overview page. It is not a
   secret.
3. Fill in `zones.tfvars` and `dns.tfvars`. Delete the example WAF, load balancer and
   account governance entries rather than leaving them in place - the example members
   are `example.com` addresses that will fail as soon as a domain allowlist is set,
   and inviting people is not something to do by accident on a first apply.

Administration, before that pull request can apply:

4. Create the GitHub Environments for the account: one `<name>-plan`, plus one
   `<name>-<layer>-apply` per layer. Each holds a Cloudflare API token scoped to that
   account and that layer, and the apply environments need required reviewers.
   Full details, including the exact token scopes, are in
   [.github/workflows/README.md](.github/workflows/README.md).

No workflow edit and no `.tf` edit. The pipeline discovers accounts from the
directory tree.

## Running the pipeline by hand

Sometimes you want to plan or apply without a code change. Both workflows have a
manual trigger, under the Actions tab, then Run workflow.

| Input | Meaning |
|---|---|
| `account` | An account directory name, or `all` |
| `layer` | A layer directory name, or `all` |

A manual run has no diff to work from, so it selects everything the inputs allow.
`all` and `all` means the entire fleet across every account. Narrow it.

Reasons you might: confirming the fleet is in the state you expect after a Cloudflare
side change, or re-running one account after fixing its configuration.

## When it goes wrong

Almost everything below is a guardrail that fired before anything reached Cloudflare,
and the fix is in the message.

### CI failed

| Message | What happened |
|---|---|
| `terraform fmt` check failed | Formatting only. The log prints the exact diff, so apply it by hand. The official Terraform extension for VS Code will also format on save. |
| `Every account var file is claimed by at least one layer` | A new file in an account tree assigns a variable no layer declares, or splits variables across two layers. One variable belongs to one file. |
| `Nothing secret is tracked in git` | Something credential shaped appeared in a committed tfvars file. Remove it and use an environment secret. |

### The plan failed

| Message | What happened |
|---|---|
| `failed to make http request` on `waf` or `load_balancing` | The zone does not exist yet. Add the zone in its own pull request first. |
| `zone_key does not match any entry in var.zones` | A typo, or you added a policy for a zone you have not declared. Valid keys are listed in the error. |
| `zone_config has entries with no matching zone in var.zones` | A key in `dns.tfvars` that is not in `zones.tfvars`. Without the check that zone would deploy with no DNS records. |
| `Unknown baseline rule name` | Misspelt catalogue entry. The error lists every valid name. |
| `A baseline WAF rule was selected without the input it depends on` | You asked for a rule whose list is empty. Fill in `waf_trusted_ip_ranges` or `waf_blocked_countries`. |
| `Two waf_policies entries target the same zone_key` | Cloudflare allows one ruleset per phase per zone. Merge the two policies. |
| `dns_records with proxied = true must use ttl = 1` | Remove the explicit TTL, or set `proxied = false`. |
| `Only A, AAAA and CNAME records can be proxied` | Set `proxied = false` on that record. |
| `dns_records contains duplicate type/name/content combinations` | Two records resolving to the same thing. Names are qualified, so `www` and `www.example.com` collide. |
| `Each zones entry must have a distinct domain_name` | One zone per domain per account. |
| `A load balancer hostname is not inside the zone it references` | `lb_hostname` must sit under that zone's domain. |
| `pool_minimum_origins ... cannot exceed the number of origins` | The pool could never become healthy. Add origins or lower the minimum. |
| `health_check_timeout ... must be shorter than health_check_interval` | Probes would overlap. |
| `must leave mitigation_timeout unset or 0` | A log-only rate limit takes no timeout. Delete the line. |
| `custom_block_rules[*].action must be one of` | Probably `skip`, which is not supported. |
| `missing: secret CLOUDFLARE_API_TOKEN (environment ...)` | The environment for that account and layer does not exist yet, or has no token. Administration, not configuration. |

### The plan wants to destroy something

Stop and work out why before approving. Renaming a key in `zones.tfvars` is the usual
cause, because keys are identity, and renaming one destroys and recreates the
resource. For a zone that means losing every DNS record in it.

If you meant to rename rather than replace, the change is not a configuration edit
and needs somebody who can move Terraform state.

### The apply is stuck waiting

That is the approval gate. Open the run and approve the pending environment. If you
are not a listed reviewer, ask one.

### The apply ran but nothing works

Check the zone is `active` rather than `pending` in the Cloudflare dashboard. If it is
pending, the registrar is not delegating to Cloudflare yet.

## For platform administrators

One time setup, not part of a normal change: the R2 state bucket and its scoped
token, the repository variables `TF_BACKEND_BUCKET` and `TF_BACKEND_ENDPOINT`, the
per account Cloudflare tokens, the GitHub Environments and their reviewers, and
branch protection with `plan complete` as the required check.

All of it, including exact token scopes and the security trade-offs, is in
[.github/workflows/README.md](.github/workflows/README.md).

## Where to go next

| Document | For |
|---|---|
| [.github/workflows/README.md](.github/workflows/README.md) | The pipeline, environments, token scopes, security notes |
| [deployment/README.md](deployment/README.md) | How layers and accounts fit together, and why |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Changing the Terraform itself rather than a customer's configuration |

Looking for what an input does or what values it accepts? Read the `description` and
`validation` blocks in the relevant layer's `variables.tf`, or the module's. That is
where the reference documentation lives.
