terraform {
  # The same floor as the parent module, for the same reason: validation rules
  # here rely on `||` short-circuiting.
  required_version = ">= 1.12.0"
}
