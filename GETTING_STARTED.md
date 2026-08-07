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

`zones` goes first, then `waf`, `load_balancing` and `r2`. The apply workflow handles
that ordering for you.

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
├── zones.tfvars                which zones exist: key -> domain name, and its tier
├── dns.tfvars                  zone settings, TLS posture, bot posture, DNS records
├── waf.tfvars                  firewall and rate limiting policies
├── load_balancing.tfvars       load balancers, pools, health checks
├── r2.tfvars                   object storage buckets, CORS, lifecycle, retention
├── account_governance.tfvars   who can sign in to the account, and with what
└── zerotrust.tfvars            Cloudflare Access: who reaches what, and how
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

### Use two pull requests if the zone also needs WAF, a load balancer or an R2 custom domain

The `waf`, `load_balancing` and `r2` layers find a zone by looking its domain name up
through the Cloudflare API. Before the zone exists there is nothing to find, so a
pull request that adds a zone *and* its WAF policy will fail the `waf` plan and you
will not be able to merge it.

Split it:

1. First pull request adds the zone. Merge and approve the apply.
2. Second pull request adds the WAF, load balancer or custom domain configuration.
   Its plan now resolves the zone and succeeds.

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
lookup, and `r2` too if a bucket is served from a hostname in it.

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

## Task: set a zone's tier

Every zone declares the Cloudflare plan it is on, in `zones.tfvars`:

```hcl
zones = {
  primary = { domain_name = "example.com", zone_tier = "business" }
  mail    = { domain_name = "example.org" }
}
```

Leave `zone_tier` out and the zone falls back to `default_zone_tier`, which is
`free`. Valid values are the plan IDs Cloudflare's API accepts: `free`, `lite`,
`pro`, `pro_plus`, `business`, `enterprise`, and the reseller equivalents
`partners_free`, `partners_pro`, `partners_business`, `partners_enterprise`,
`partners_ent`.

It lives in `zones.tfvars` rather than `dns.tfvars` because the `waf` layer needs
it too, and that layer is only ever given the inventory file.

**By default this describes the plan, it does not buy it.** Nothing in a normal
run changes a Cloudflare subscription. What `zone_tier` does is gate features: a
bot management setting the plan cannot support fails the plan, naming the field
and the tier it needs, instead of failing mid-apply with a Cloudflare error that
names neither.

If you do want Terraform to own the plan itself, set
`manage_zone_subscriptions = true` on the `zones` layer, or `manage_subscription
= true` on one zone in `dns.tfvars`. Read the warning under "Managing
subscriptions changes billing" before you do.

## Task: control bot and AI crawler traffic

Bot handling is split across two layers, and the split is not arbitrary.
Cloudflare allows exactly one entry-point ruleset per phase per zone, and the
`waf` layer already owns the phase the per-category rules need.

**Coarse, zone-level posture, in `dns.tfvars`:**

```hcl
zone_config = {
  primary = {
    bot_management = {
      sbfm_definitely_automated = "block"
      sbfm_likely_automated     = "managed_challenge"
      sbfm_verified_bots        = "allow"

      ai_bots_protection = "block"
      crawler_protection = "enabled"
    }
  }
}
```

**Per-behaviour rules, in `waf.tfvars`:**

```hcl
waf_policies = {
  primary = {
    zone_key = "primary"

    bot_traffic = {
      search   = "allow"
      agent    = "managed_challenge"
      training = "block"
    }
  }
}
```

The three behaviours are Cloudflare's current AI bot taxonomy:

| Behaviour | What the bot is doing |
|---|---|
| `search` | Indexes your content so it can answer questions about it later |
| `agent` | Acts in real time on a person's behalf, such as a chat fetch bot or a browser-use agent |
| `training` | Crawls your content to train or fine-tune a model, absorbing it permanently |

Each takes `allow`, `log`, `managed_challenge`, `js_challenge`, `challenge` or
`block`. Leave one out and that behaviour is not touched.

Two things worth understanding before you rely on this:

- **These rules only see verified bots.** A crawler that does not identify
  itself, or spoofs a browser user agent, has no category and passes straight
  through them. That traffic is what `ai_bots_protection` in `dns.tfvars` is for.
  Use both.
- **`allow` is a skip.** The bot rules are emitted at the top of the zone's
  custom ruleset, ahead of the baseline and your own rules, and `allow` stops
  evaluation there. That ordering is the whole point: it is what lets search
  crawlers through a baseline that would otherwise challenge them. It also means
  an over-broad `allow` skips your own rules, so keep the categories tight.

Bot rules need the zone on `bot_traffic_min_tier` or above, which defaults to
`pro`. Set the zone's real `zone_tier` and the plan tells you if it is short.

Which categories a behaviour matches is in
`modules/waf/locals.tf`. If Cloudflare adds one before this repository does,
override it per policy rather than waiting:

```hcl
bot_traffic = {
  training           = "block"
  category_overrides = { training = ["AI Crawler", "Some New Category"] }
}
```

Check the `bot_traffic_rules` output after a plan to confirm what each behaviour
actually resolved to.

## Managing subscriptions changes billing

`manage_zone_subscriptions = true` makes `terraform apply` set each zone's rate
plan. Before turning it on:

- **An upgrade is charged to the account.** A typo in `zone_tier` is a billing
  event, not a validation error.
- **A downgrade takes effect immediately on a live zone**, stripping entitlements
  such as WAF rule allowances, rate limiting and Bot Management in the same
  apply that changes the plan.
- **The token needs Billing Read and Billing Write**, which the layer otherwise
  does not require. Use a separate, deliberately scoped token for that run rather
  than adding billing rights to the token used for routine DNS work.

The plan prints a warning listing every zone whose plan the run would change.
Read it. It is a `check`, so it does not block the apply.

## Task: add an R2 bucket

Edit `deployment/accounts/<account>/r2.tfvars`. The key is the Terraform address,
`name` is the bucket in Cloudflare, and both are permanent - changing either
destroys and recreates the bucket, which takes every object with it. R2 has no
versioning, so nothing comes back.

```hcl
r2_buckets = {
  app_uploads = {
    name = "account-a-app-uploads"

    lifecycle_rules = [
      { id = "expire-raw", prefix = "raw/", delete_objects_after_days = 30 },
    ]
  }
}
```

That is the whole thing for a private bucket read server-side. Leave
`lifecycle_rules` out entirely and the bucket inherits the platform baseline,
which aborts incomplete multipart uploads after seven days - worth having,
because those parts bill like stored objects and never show up in a listing.

Ages are in whole days. The two `*_on_date` fields are the exception and want a
full timestamp, `2027-01-01T00:00:00Z`, because R2 rejects a bare date.

### Serving a bucket publicly

Put it on a hostname in a zone you own:

```hcl
public_assets = {
  name = "account-a-public-assets"

  custom_domains = [
    { zone_key = "primary", hostname = "assets.example.com" },
  ]

  cors_rules = [
    {
      allowed_origins = ["https://app.example.com"]
      allowed_methods = ["GET", "HEAD"]
    },
  ]
}
```

The hostname must sit inside that zone's domain, and the zone has to exist
already - see [the two-pull-request note](#use-two-pull-requests-if-the-zone-also-needs-waf-a-load-balancer-or-an-r2-custom-domain).

**Do not also add the hostname to `dns.tfvars`.** Cloudflare creates the DNS
record for you when the custom domain is attached, and that record is owned by
R2 rather than by you. The `zones` layer will not delete it - it only manages
records it created itself - but if you declare the same hostname there as well,
its apply tries to create a record that already exists and fails. One hostname,
one place: `r2.tfvars`.

Everything in a bucket served this way is public. R2 has no per-object
permissions, so anyone who knows or guesses a key can read it. Put a Worker or
Cloudflare Access in front of anything that is not genuinely meant for the world.

The plan will refuse `public_r2_dev_domain = true`, which is the `pub-<hash>.r2.dev`
URL. It serves the same content with no cache, no branding and no zone controls,
and Cloudflare means it for development. A custom domain is the answer for
anything real. It will also refuse `allowed_origins = ["*"]` - list the origins
that need access.

### Retention

`lock_rules` stops objects being deleted or overwritten until retention expires.
Nobody can override it: not the application, not an operator with full R2
credentials, and not this pipeline.

```hcl
lock_rules = [
  { id = "retain-audit-logs", prefix = "audit/", retain_for_days = 365 },
]
```

Add one only where somebody has asked for it in writing. `retain_indefinitely`
means those objects, and the bucket holding them, can never be removed.

Keep lock prefixes clear of any lifecycle rule that deletes. R2 accepts the
combination and then refuses each deletion silently, so the storage is paid for
indefinitely; the plan fails rather than letting that happen.

### What is not here

R2 access keys, and objects. A key is a credential and credentials never enter
Terraform state. Uploading objects is the application's job - if you genuinely
need Terraform to place a file in a bucket, that is the AWS provider's
`aws_s3_object` against the R2 S3 endpoint, and it needs a credential this
repository deliberately does not hold.

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

## Task: put an application behind Cloudflare Access

Edit `deployment/accounts/<account>/zerotrust.tfvars`. Four things live there:
the login methods Access offers, the audiences it recognises, the policies it
evaluates, and the applications those policies protect.

Read a plan from this file as carefully as the account governance one. It
decides who reaches internal systems, and a destroy here shuts a door somebody
is standing at.

### Before the first apply on a new account: the team name

Cloudflare Access lives under a team domain, `<team>.cloudflareaccess.com`. An
account that has never used Zero Trust has not chosen one, and **Terraform
cannot choose it for you** - the Cloudflare provider updates the Zero Trust
organization rather than creating it, so there has to be one to update.

Do it once, in the dashboard under Zero Trust, then Settings, then Custom Pages,
which asks for the team name the first time the section is opened. Then set it
in the account tree:

```hcl
zero_trust_team_name         = "acme"
zero_trust_organization_name = "Acme Internal Applications"
```

Leave `zero_trust_team_name` out entirely and the layer adopts whatever team
name the account already has, which is what you want when taking over an account
somebody configured by hand.

Getting it wrong is worse than it looks, so the plan refuses it. Changing the
team name renames the team domain: every Access application URL changes, every
enrolled WARP device has to re-enrol, every bookmark breaks, and the old name is
released for anybody else to register. If the rename really is intended, set
`allow_team_name_change = true` in
`deployment/layers/zerotrust/defaults.auto.tfvars`, apply, and set it back.

### Adding an application

```hcl
access_groups = {
  platform_engineers = {
    name = "Platform Engineers"
    include = {
      # The Entra group's object ID, copied from Entra. Not its name.
      entra_groups = [
        { identity_provider_key = "entra_id", group_id = "22222222-2222-2222-2222-222222222222" },
      ]
    }
  }
}

access_policies = {
  platform_engineers_mfa = {
    name     = "Platform Engineers with MFA"
    decision = "allow"
    include  = { group_keys = ["platform_engineers"] }
    require  = { auth_methods = ["mfa"] }
  }
}

access_applications = {
  grafana = {
    name        = "Grafana"
    domain      = "grafana.example.com"
    policy_keys = ["platform_engineers_mfa"]
  }
}
```

Keys, not IDs. A policy names its groups by key, an application names its
policies by key, and a rule names its identity provider by key. Get one wrong
and the plan fails listing the keys that do exist.

`policy_keys` is **ordered**. Cloudflare evaluates an application's policies in
the order they are listed and the first match decides, so a `deny` goes at the
front. Reordering the list is a real change and will show in the plan.

Two things that catch people out. The hostname's DNS record has to exist and be
proxied, or the request never reaches Cloudflare and Access never sees it - that
is a `dns.tfvars` change in the `zones` layer, not here. And `auth_methods =
["mfa"]` means the identity provider asserted the user completed multi-factor;
it is not Cloudflare prompting for a second factor.

### More than one hostname, or a private one

Add them with `extra_destinations`:

```hcl
access_applications = {
  grafana = {
    name        = "Grafana"
    domain      = "grafana.example.com"
    policy_keys = ["platform_engineers_mfa"]

    extra_destinations = [
      # Another public hostname the same app answers on. Needs its own proxied
      # DNS record.
      { uri = "metrics.example.com" },

      # Something only reachable over WARP, by IP range or by SNI.
      { type = "private", cidr = "10.10.0.0/24", l4_protocol = "tcp", port_range = "5432" },
      { type = "private", hostname = "db.internal" },
    ]
  }
}
```

Do not restate `domain` here - the layer adds it to the list itself, and the
plan fails if you list it twice. That matters more than it looks: Cloudflare
treats the destinations list as the *complete* set of what Access secures, so an
application whose list left its own hostname out would look protected in the
dashboard and would not be.

This replaces `self_hosted_domains`, which Cloudflare deprecated in provider 5.x
and supported only until 21 November 2025.

### Connecting Microsoft Entra ID

Create an app registration in Entra, then:

```hcl
identity_providers = {
  entra_id = {
    name = "Entra ID"
    type = "azureAD"
    config = {
      client_id    = "<Application (client) ID>"
      directory_id = "<Directory (tenant) ID>"

      # Without this, Entra never sends group membership and every entra_groups
      # rule silently matches nobody.
      support_groups = true
    }
    scim_config = {
      enabled          = true
      user_deprovision = true
      seat_deprovision = true
    }
  }
}
```

**The client secret does not go in this file, or in any file.** It reaches
Terraform from the pipeline as `TF_VAR_identity_provider_secrets`, a JSON object
keyed the same way as `identity_providers`, held as a secret on the account's
`zerotrust` apply environment:

```
TF_VAR_IDENTITY_PROVIDER_SECRETS = {"entra_id":"<the client secret>"}
```

A secret typed into a `.tfvars` is committed by the next `git add`, because
account trees are deliberately committable. The plan fails if a provider that
needs a secret has no entry, and fails again if there is an entry for a provider
that no longer exists - a secret nobody rotates is a secret nobody misses.

Note that the secret ends up in Terraform state in plain text regardless, along
with the client secret of every service token, because Cloudflare stores them
and Terraform records what it sent. That is why state and plan files for this
layer are treated as credential material rather than configuration. Rotating the
Entra secret means rotating it in Entra, updating the environment secret, and
re-applying.

### Giving a machine access

A service token is a client ID and secret pair a caller sends in
`CF-Access-Client-Id` and `CF-Access-Client-Secret` headers.

```hcl
service_tokens = {
  ci_pipeline = { name = "CI Pipeline" }
}

access_policies = {
  ci_service_token = {
    name     = "CI Pipeline Service Token"
    decision = "non_identity"
    include  = { service_token_keys = ["ci_pipeline"] }
  }
}
```

`non_identity`, not `allow`: there is no person to authenticate. Set
`service_auth_401_redirect = true` on any application a machine calls, so a
failed call gets a 401 rather than a page of login HTML that the caller will
parse as a successful response.

Cloudflare shows the generated secret once. It is not an output of this layer -
that would put it in the plan comment on the pull request - so read it from the
dashboard when the token is first created and put it straight into whatever
secret store the caller uses.

### What the plan will refuse

- **`decision = "bypass"`.** It removes authentication entirely from every
  application the policy is attached to. Restricted by default; allowing it
  means editing `restricted_policy_decisions` in
  `deployment/layers/zerotrust/defaults.auto.tfvars` on a pull request that says
  why.
- **An email or domain outside the permitted list**, if `allowed_email_domains`
  is set for this deployment. Only `include` rules are checked - excluding an
  outside address is not the problem.
- **An application whose policies all say deny**, which nobody could reach.
- **A rule set with no conditions in it**, which is a restriction somebody
  believes is in force and is not.
- **A key matching nothing** - a group, policy, service token or identity
  provider key that does not exist.
- **`group_keys` inside an `access_groups` rule.** A group nesting another group
  the layer also creates is a Terraform dependency cycle. Use `group_ids` for a
  group managed elsewhere, or merge the two rule sets.

One more that is a provider limitation rather than a guardrail:
`allowed_idp_keys` on an application cannot name an identity provider created in
the same run, and the failure is an unhelpful provider error about unknown
values. Apply the provider first and the application after, or use
`login_method_keys` in a policy instead - which is enforced rather than merely
displayed on the login page.

## Task: onboard a customer account

Part of this is configuration and part of it is administration, so expect to need
somebody with repository admin rights.

Configuration, in a pull request:

1. Create `deployment/accounts/<name>/` and copy the seven files from `account_a`.
2. Put the real Cloudflare account ID in `account.tfvars`. It is the 32 character hex
   string in the dashboard URL, and also on any zone's Overview page. It is not a
   secret.
3. Fill in `zones.tfvars` and `dns.tfvars`. Delete the example WAF, load balancer,
   account governance and Zero Trust entries rather than leaving them in place - the
   example members are `example.com` addresses that will fail as soon as a domain
   allowlist is set, inviting people is not something to do by accident on a first
   apply, and the example Access application points at a hostname the account does
   not own.

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
| `failed to make http request` on `waf`, `load_balancing` or `r2` | The zone does not exist yet. Add the zone in its own pull request first. |
| `zone_key does not match any entry in var.zones` | A typo, or you added a policy for a zone you have not declared. Valid keys are listed in the error. |
| `zone_config has entries with no matching zone in var.zones` | A key in `dns.tfvars` that is not in `zones.tfvars`. Without the check that zone would deploy with no DNS records. |
| `Unknown baseline rule name` | Misspelt catalogue entry. The error lists every valid name. |
| `A baseline WAF rule was selected without the input it depends on` | You asked for a rule whose list is empty. Fill in `waf_trusted_ip_ranges` or `waf_blocked_countries`. |
| `Two waf_policies entries target the same zone_key` | Cloudflare allows one ruleset per phase per zone. Merge the two policies. |
| `bot_traffic is configured on a zone below bot_traffic_min_tier` | The zone's `zone_tier` in `zones.tfvars` is below `pro`. Set the plan the zone is really on, or drop `bot_traffic` for that policy. |
| `bot_management sets fields the zone's tier does not support` | A plan-locked setting on too low a tier. The error names each field and the tier it needs. |
| `bot_management sets fight_mode = true alongside sbfm_*` | Bot Fight Mode and Super Bot Fight Mode are the same control at two plan levels. Set one. |
| `bot_traffic.category_overrides sets an empty category list` | An override with no categories would emit `in {}`, which Cloudflare rejects. Remove the behaviour instead. |
| `BILLING: this run manages the Cloudflare rate plan for N zone(s)` | A warning, not an error. `manage_zone_subscriptions` is on, so the apply will change plans and billing. |
| `dns_records with proxied = true must use ttl = 1` | Remove the explicit TTL, or set `proxied = false`. |
| `Only A, AAAA and CNAME records can be proxied` | Set `proxied = false` on that record. |
| `dns_records contains duplicate type/name/content combinations` | Two records resolving to the same thing. Names are qualified, so `www` and `www.example.com` collide. |
| `Each zones entry must have a distinct domain_name` | One zone per domain per account. |
| `A load balancer hostname is not inside the zone it references` | `lb_hostname` must sit under that zone's domain. |
| `pool_minimum_origins ... cannot exceed the number of origins` | The pool could never become healthy. Add origins or lower the minimum. |
| `health_check_timeout ... must be shorter than health_check_interval` | Probes would overlap. |
| `must leave mitigation_timeout unset or 0` | A log-only rate limit takes no timeout. Delete the line. |
| `custom_block_rules[*].action must be one of` | Probably `skip`, which is not supported. |
| `These buckets ask for anonymous public access on their r2.dev URL` | The r2.dev domain serves every object to anyone. Use a `custom_domains` entry, or unlock `allow_public_r2_dev_domains` on its own pull request. |
| `These CORS rules allow every origin on the internet` | `allowed_origins = ["*"]`. List the origins that actually need access. |
| `These lifecycle rules delete objects with an empty prefix` | That is the whole bucket on a schedule, and R2 has no versioning. Scope it with a `prefix`. |
| `A lifecycle rule would delete objects that an object lock rule retains` | R2 accepts both and then refuses the deletion silently, so the storage is paid for forever. Narrow one of the two prefixes. |
| `A custom domain hostname is not inside the zone it references` | The hostname must sit under that zone's domain. |
| `Each lifecycle_rules[*] date must be a full RFC3339 timestamp` | `2027-01-01` is rejected by R2; write `2027-01-01T00:00:00Z`. |
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

For an Access application specifically: check the DNS record for its hostname exists
and is **proxied**. An unproxied record bypasses Cloudflare entirely, so Access never
sees the request and the origin answers it directly - which looks exactly like Access
being switched off, because for that hostname it is.

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
