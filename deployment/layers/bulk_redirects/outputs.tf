output "bulk_redirect_lists" {
  description = <<-EOT
    Per-list identifiers, keyed by list key. `list_id` is what the load step
    needs:

      LIST_ID=$(terraform -chdir=deployment/layers/bulk_redirects \
                  output -json bulk_redirect_lists | jq -r '.<list_key>.list_id')
      tools/redirects/load-bulk-redirect-list.py --list-id "$LIST_ID" --items ./items.json

    `num_items` counts every row Cloudflare holds, including rows loaded outside
    Terraform. `managed_item_count` counts only the rows this layer owns, and is
    zero on any list whose data comes from the load step - which is the expected
    reading, not a fault.
  EOT
  value = {
    for key, list in module.bulk_redirect_lists : key => {
      list_id            = list.list_id
      name               = list.name
      num_items          = list.num_items
      managed_item_count = list.managed_item_count
      manage_items       = list.manage_items
    }
  }
}

output "bulk_redirect_ruleset" {
  description = "The account's http_request_redirect entry-point ruleset. `expressions` is worth reading after a first apply: it is exactly what Cloudflare evaluates, so a scope that came out wider or narrower than intended is visible here rather than in traffic. `disabled_rules` names lists that are loaded but switched off."
  value = {
    ruleset_id     = module.bulk_redirect_ruleset.ruleset_id
    rule_count     = module.bulk_redirect_ruleset.rule_count
    expressions    = module.bulk_redirect_ruleset.expressions
    disabled_rules = module.bulk_redirect_ruleset.disabled_rules
  }
}

output "unloaded_lists" {
  description = "Lists that Terraform does not own the rows of and which Cloudflare currently reports as empty. Expected between a first apply and the load step; anything lingering here afterwards is a list whose data load did not run or did not succeed."
  value = sort([
    for key, list in module.bulk_redirect_lists : key
    if !list.manage_items && list.num_items == 0
  ])
}
