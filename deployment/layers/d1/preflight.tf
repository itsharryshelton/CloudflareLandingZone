# Cross-variable checks. A module block cannot carry lifecycle.precondition and
# variable validation cannot compare two variables, so they live on a state-only
# resource from Terraform's built-in provider.
#
# The adoption check reads data.cloudflare_d1_databases, which is resolved at
# plan time, so it fires before the plan is approved rather than during apply.

resource "terraform_data" "preflight" {
  input = {
    d1_databases = length(var.d1_databases)
  }

  lifecycle {
    precondition {
      condition     = length(local.replicated_d1_in_jurisdiction) == 0
      error_message = "These D1 databases are restricted to a jurisdiction and have read replication on: ${join("; ", local.replicated_d1_in_jurisdiction)}. Replication keeps a copy of the data in every supported region, which is the opposite of what the jurisdiction was set to achieve. Set read_replication_mode = \"disabled\" on the database, check default_d1_read_replication_mode, or set allow_replicated_d1_in_jurisdiction = true if the jurisdiction was a latency preference rather than a compliance requirement."
    }

    precondition {
      condition     = length(local.adopted_jurisdiction_mismatches) == 0
      error_message = "These databases already exist under a different jurisdiction from the one d1.tfvars declares: ${join("; ", local.adopted_jurisdiction_mismatches)}. Jurisdiction is fixed at creation, so adopting them as declared would destroy and recreate them empty. Set jurisdiction in d1.tfvars to what exists, or give the entry a different name if a separate database under the declared jurisdiction is what was meant."
    }

    # Tags are written after the apply by a job that only sees the output, so a
    # bad key would otherwise surface there - after this plan was approved.
    precondition {
      condition     = length(local.resource_tag_problems) == 0
      error_message = "resource_tags in accounts/<account>/tags.tfvars: ${join("; ", local.resource_tag_problems)}."
    }
  }
}
