# Cloudflare Origin Pull CA

`cloudflare_origin_pull_ca.pem` is Cloudflare's public Origin Pull CA, vendored
so the layer's `origin_trust_bundles` output is complete without a network fetch
at plan time. It is a certificate, not a key: it is public material, published by
Cloudflare, and presented on every origin handshake.

It is what an origin has to trust to verify the client certificate Cloudflare
presents **by default** - that is, on any zone or hostname that has not been
given a certificate of its own through `origin_pull_certificates`.

| | |
|---|---|
| Source | <https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem> |
| Subject | `C=US, O=CloudFlare, Inc., OU=Origin Pull, L=San Francisco, ST=California, CN=origin-pull.cloudflare.net` (as `openssl x509 -subject` prints it) |
| Expires | 2029-11-01 |
| SHA-256 | `9A:1A:C2:B4:BE:15:F9:F2:7E:EE:20:A7:34:CB:A4:E9:89:8F:61:00:1B:3B:D7:C8:4B:69:B5:6A:3E:25:A2:B9` |

## Refreshing it

Cloudflare rotates this CA. When they do, replace the file and check the
fingerprint on the pull request rather than taking the download on trust:

```bash
curl -fsS https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem \
  -o deployment/layers/origin_pulls/ca/cloudflare_origin_pull_ca.pem
openssl x509 -in deployment/layers/origin_pulls/ca/cloudflare_origin_pull_ca.pem \
  -noout -subject -dates -fingerprint -sha256
```

Update the table above in the same commit. An account that needs a different
value before the template is bumped can set
`cloudflare_origin_pull_ca_certificate` in its own tfvars, which wins over this
file.
