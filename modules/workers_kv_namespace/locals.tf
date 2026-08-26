# Derives the values main.tf's preconditions assert on. There is no mapping to do
# here: the KV API takes the operator-facing shape almost verbatim.

locals {
  pair_count = length(var.pairs)

  # 25 MiB is Cloudflare's per-value ceiling. `length()` counts Unicode
  # characters rather than bytes, so a multi-byte value trips this later than the
  # API would - deliberately, because the point is to catch "somebody pasted a
  # file into a variable", not to shave the last megabyte.
  oversized_pairs = [
    for key, pair in var.pairs : key
    if length(pair.value) > 26214400
  ]
}
