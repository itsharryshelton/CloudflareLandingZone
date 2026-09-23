# `data/kv` - KV data files Terraform owns

A file here is referenced by `kv_namespaces[*].pairs_file` in an account tree and
becomes one `cloudflare_workers_kv` resource per key. `pairs_file` is relative to
this directory (`kv_data_dir`): `pairs_file = "flags.json"` reads
`layers/workers/data/kv/flags.json`. It must be a `.json` name with no `..`, and a
namespace cannot also set `pairs`. A missing file, a repeated key, or more entries
than `default_max_managed_kv_pairs` (500) - or the namespace's own
`max_managed_pairs` - fails the plan.

Format is Cloudflare's bulk format, which is what the KV bulk API and
`wrangler kv bulk put` both take:

```json
[
  { "key": "/old/path", "value": "/new/path;301", "base64": false },
  { "key": "/other", "value": "https://example.com/thing;302", "base64": false }
]
```

Only `key`, `value`, `base64` and `metadata` are read; `expiration` and
`expiration_ttl` are ignored. `base64: true` means the value is base64-encoded and
is decoded before it is written, and the decoded bytes must be UTF-8 text, so a
binary value cannot go through a `pairs_file`. `metadata` is optional and is
stored alongside the value: an object is JSON-encoded, and a string must itself
be JSON.

## What belongs here, and what does not

This is for configuration-shaped data - a few hundred keys at most, where the
value belongs in a pull request next to the Worker that reads it. Terraform holds
every value in state, prints it in a plan, reads every key on every plan, and
writes each changed key with its own API call.

A dataset - a redirect table, a catalogue - does not belong here at any size that
would make it interesting. Declare the namespace with no `pairs` or `pairs_file`
and commit the dataset to `layers/workers/data/bulk/`, named after the namespace
title minus a trailing `-prod`, `-dev`, `-stage` or `-test` - `redirects-uk-prod`
and `redirects-uk-dev` both read `data/bulk/redirects-uk.json`. Any other title is
used whole: `account-a-config` reads `data/bulk/account-a-config.json`.

After every successful `workers` apply,
[`kv-bulk-load.sh`](../../../../../.github/scripts/kv-bulk-load.sh) loads it
against the ID the layer outputs, in chunks of 10,000, then deletes **every key in
the namespace that the file does not list** - including keys the application
wrote at runtime and any `pairs` or `pairs_file` keys. A namespace fed from
`data/bulk` must be owned by that file alone. A namespace with no matching file is
skipped. Every file is validated before anything is written: a JSON array whose
entries all have `key` and `value`, with no repeated key and no value (up to its
first `;`) equal to its own key.

To reproduce the pipeline step by hand, from a directory initialised against the
layer's state, with jq, terraform and npx on the path:

```bash
CLOUDFLARE_API_TOKEN=... CLOUDFLARE_ACCOUNT_ID=... \
  bash .github/scripts/kv-bulk-load.sh deployment/layers/workers
```

A bare `wrangler kv bulk put` against the namespace ID in the `kv_namespaces`
output does less: no chunking, no validation, and no removal of stale keys.

Terraform still owns the namespace, the Worker and the binding; only the rows are
outside it.

## Nothing secret

Values here are committed to git, held in Terraform state and printed in plan
output. A Worker reads secrets from a `secrets_store_secret` binding, never from
KV.
