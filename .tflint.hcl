config {
  call_module_type = "all"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Enforce a documented interface on every module in this repository.
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

rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}
