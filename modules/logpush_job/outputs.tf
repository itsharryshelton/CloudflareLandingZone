# No destination_conf and no ownership_challenge: either may carry a
# credential, and an output ends up in a plan log.

output "id" {
  description = "Logpush job ID. What the dashboard, the API and `terraform import` refer to the job by."
  value       = cloudflare_logpush_job.this.id
}

output "name" {
  description = "Job name as Cloudflare holds it."
  value       = cloudflare_logpush_job.this.name
}

output "dataset" {
  description = "Dataset the job pushes."
  value       = cloudflare_logpush_job.this.dataset
}

output "scope" {
  description = "\"zone\" or \"account\" - where the job reads its dataset from."
  value       = local.scope
}

output "enabled" {
  description = "Whether the job is pushing."
  value       = cloudflare_logpush_job.this.enabled
}
