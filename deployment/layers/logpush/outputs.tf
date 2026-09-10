output "logpush_jobs" {
  description = "Job ID, name, dataset, scope and enabled flag per logical key. No destination: it may carry a credential, and an output ends up in a plan log."
  value = {
    for key, job in module.logpush_jobs : key => {
      id      = job.id
      name    = job.name
      dataset = job.dataset
      scope   = job.scope
      enabled = job.enabled
    }
  }
}
