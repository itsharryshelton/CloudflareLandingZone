resource "terraform_data" "preflight" {
  input = {
    account_lists = length(var.account_lists)
  }

  lifecycle {
    precondition {
      condition     = length(local.ignored_items) == 0
      error_message = "These lists supply items but leave manage_items false, so the rows would be silently dropped while the config reads as though the list were populated: ${join("; ", local.ignored_items)}. Set manage_items = true to have Terraform own the rows, or remove them and load the list through the Lists API."
    }
  }
}
