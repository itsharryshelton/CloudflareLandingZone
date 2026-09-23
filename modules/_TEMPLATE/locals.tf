# Normalisation and mapping layer.
#
# Every module keeps the logic that turns operator-facing variables into
# provider-shaped values here, so main.tf reads as a plain declaration of
# resources. See modules/zone_base/locals.tf and modules/waf/locals.tf for
# worked examples.
#
# Rules of thumb:
#   - Cheap, single-field checks (types, enums, ranges, required fields) belong
#     in validation blocks in variables.tf. They fail before any graph is built
#     and give the operator a precise message.
#   - Anything needing cross-field or cross-item reasoning (uniqueness of a
#     derived key, one variable compared against another) is derived here and
#     asserted with a lifecycle precondition in main.tf, so every cross-field
#     rule is in one file. (The deployment layers centralise theirs in
#     preflight.tf for the same reason.)
#   - Normalise inputs to the shape the Cloudflare API returns (e.g. fully
#     qualified DNS names, upper-cased record types) so plans stay empty after
#     the first apply.

# locals {
#   items = { for item in var.records : item.name => item }
# }
