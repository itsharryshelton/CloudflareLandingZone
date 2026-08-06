output "member_ids" {
  value       = { for key, member in cloudflare_account_member.this : key => member.id }
  description = "Membership ID per email address. These are the IDs another module or a manual import needs; they are not the user's account ID."
}

output "member_statuses" {
  value       = { for key, member in cloudflare_account_member.this : key => member.status }
  description = "Invitation state per email address. Anything still \"pending\" means the person has not accepted the emailed invitation yet and cannot sign in."
}

output "user_group_ids" {
  value       = { for key, group in cloudflare_user_group.this : key => group.id }
  description = "User group ID per normalised group name."
}

output "user_group_names" {
  value       = { for key, group in cloudflare_user_group.this : key => group.name }
  description = "Display name per normalised group name, as it appears in the Cloudflare dashboard."
}
