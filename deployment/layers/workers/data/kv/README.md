# `data/kv` - KV data files Terraform owns

A file here is referenced by `kv_namespaces[*].pairs_file` in an account tree and
becomes one `cloudflare_workers_kv` resource per key. Format is Cloudflare's bulk
format, which is what the KV bulk API and `wrangler kv bulk put` both take:

```json
[
  { "key": "/old/path", "value": "/new/path;301", "base64": false },
  { "key": "/other", "value": "https://example.com/thing;302", "base64": false }
]
```

`base64: true` means the value is base64-encoded and is decoded before it is
written. `metadata` is optional and is stored alongside the value.

## What belongs here, and what does not

This is for configuration-shaped data - a few hundred keys at most, where the
value belongs in a pull request next to the Worker that reads it. Terraform holds
every value in state, prints it in a plan, and issues one API call per key on
every apply.

A dataset - a redirect table, a catalogue - does not belong here at any size that
would make it interesting. Declare the namespace with no `pairs_file`, and load it
from the pipeline against the ID the layer outputs:

```bash
NAMESPACE_ID=$(terraform -chdir=deployment/layers/workers output -json kv_namespaces \
                 | jq -r '.<namespace_key>.namespace_id')
wrangler kv bulk put ./dataset.json --namespace-id "$NAMESPACE_ID" --remote
```

Terraform still owns the namespace, the Worker and the binding; only the rows are
outside it.

## Nothing secret

Values here are committed to git, held in Terraform state and printed in plan
output. A Worker reads secrets from a `secrets_store_secret` binding, never from
KV.
