# One Workers KV namespace, plus any key/value pairs Terraform is asked to own.
#
# The namespace and its contents are deliberately separable. A namespace is
# infrastructure - it has an ID that bindings point at, and destroying it takes
# every key with it - while the contents are usually data, written by the
# application or by a pipeline step. Managing a few configuration keys here is
# supported and useful; managing a dataset is not, which is what the
# max_managed_pairs precondition is for.

resource "cloudflare_workers_kv_namespace" "this" {
  account_id = var.account_id
  title      = var.title

  lifecycle {
    precondition {
      condition     = local.pair_count <= var.max_managed_pairs
      error_message = "This namespace declares ${local.pair_count} pairs, over the max_managed_pairs ceiling of ${var.max_managed_pairs}. Terraform writes one key per API call and keeps every value in state, so a dataset this size makes each plan unreadable and each apply slow. Load it with `wrangler kv bulk put --namespace-id <id> <file.json>` from the pipeline and leave Terraform owning the namespace and the binding, or raise the ceiling on a pull request that says why."
    }

    precondition {
      condition     = length(local.oversized_pairs) == 0
      error_message = "These pairs exceed the 25 MiB per-value limit: ${join(", ", local.oversized_pairs)}. Cloudflare rejects the write, and Terraform would carry the whole value in state until it did."
    }
  }
}

# `for_each` over the key name, so adding or removing a key never disturbs the
# others. The namespace is referenced through the resource rather than through
# var, so Terraform orders creation without a depends_on.
resource "cloudflare_workers_kv" "this" {
  for_each = var.pairs

  account_id   = var.account_id
  namespace_id = cloudflare_workers_kv_namespace.this.id

  key_name = each.key
  value    = each.value.value
  metadata = each.value.metadata
}
