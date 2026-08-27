# TFLint configuration for the platform-management repository.
#
# ci.yml points TFLINT_CONFIG_FILE at this file with an absolute path, so
# `tflint --recursive` keeps using it as it descends into each layer rather than
# falling back to defaults per directory.
#
# This repository holds root modules (deployment/layers/*), not reusable modules.
# The modules themselves are linted by cloudflare-platform-modules' own CI.

config {
  # `local` rather than `all`: the lint job deliberately does not run
  # `terraform init`, so no remote module is on disk to descend into. `all`
  # would fail on the first git:: source instead of linting what is here.
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# A layer's variables are its operator interface - the tfvars an engineer writes
# are validated against these, so an undocumented or untyped one is a trap.
rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}

rule "terraform_naming_convention" {
  enabled = true
}

# Both are pinned per layer in terraform.tf. Drifting off a pin is how a state
# file gets written by a provider version nobody chose.
rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

# Every layer sources its modules from the modules repository unpinned, and each
# one carries a comment showing the `?ref=vX.Y.Z` form to switch to. That pin is
# a deliberate, separate decision - see deployment/README.md - so until it is
# taken this rule reports thirteen known warnings and nothing else, which trains
# people to ignore lint output. Re-enable it the moment the layers pin a tag.
rule "terraform_module_pinned_source" {
  enabled = false
}