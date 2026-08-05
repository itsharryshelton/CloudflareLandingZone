# Module implementation. Resource declarations only - normalisation and mapping
# belong in locals.tf, single-field guardrails in variables.tf.
#
# Conventions (see README.md in this directory and CONTRIBUTING.md):
#   - Name the primary resource "this".
#   - Do NOT declare a provider block here; providers are configured by the root.
#   - Use for_each with a stable key (not count over a list) for collections, so
#     reordering inputs never forces replacement.
#   - Guard optional resources with count = length(var.x) > 0 ? 1 : 0.
#   - Keep the operator-facing variable schema stable; map it onto provider
#     attributes in locals.tf.
#   - Use lifecycle.precondition for rules that variable validation cannot
#     express: cross-variable comparisons, and uniqueness of derived keys.

# resource "cloudflare_example" "this" {
#   for_each = local.items
#
#   zone_id = var.zone_id
#
#   lifecycle {
#     precondition {
#       condition     = length(local.duplicate_keys) == 0
#       error_message = "records contains duplicates: ${join(", ", local.duplicate_keys)}."
#     }
#   }
# }
