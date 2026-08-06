output "member_ids" {
  description = "Membership ID per email address. This is the ID a user group references, and the one an import needs."
  value       = module.account_governance.member_ids
}

output "member_statuses" {
  description = "Invitation state per email address. \"pending\" means the person has not yet accepted the emailed invitation and cannot sign in - the usual reason a member appears to have been added but nothing works."
  value       = module.account_governance.member_statuses
}

output "user_groups" {
  description = "User group ID and display name, keyed by the normalised group name."
  value = {
    for key, id in module.account_governance.user_group_ids : key => {
      id   = id
      name = module.account_governance.user_group_names[key]
    }
  }
}
