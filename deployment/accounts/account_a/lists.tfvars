# Account: Your-Org - account-scoped Cloudflare Lists. Consumed by the lists layer only.
#
#   terraform -chdir=layers/lists plan \
#     -var-file=../../accounts/your-org/account.tfvars \
#     -var-file=../../accounts/your-org/lists.tfvars
#
# A list here is an empty named container until something references it. The WAF
# rule that reads the blocklist below is the `block_listed_ips` baseline, selected
# in waf.tfvars - the two are joined only by the name matching, so changing one
# means changing the other.

account_lists = {
  global_ip_blocklist = {
    name         = "yourorg_global_ip_blocklist"
    kind         = "ip"
    description  = "Addresses blocked from every org domain. Maintained operationally, not in Terraform - see lists.tfvars."
    manage_items = false
  }
}
