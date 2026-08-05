# Every variable MUST have a type and a description (enforced by tflint).
# Provide sane, secure defaults where one exists; leave truly required inputs
# without a default. Add validation blocks for constrained values.
#
# The declarations below are commented out so the template lints clean. Uncomment
# and adapt when you copy this directory to modules/<name>.

# variable "zone_id" {
#   type        = string
#   description = "Target Cloudflare Zone ID (typically module.zone_base.zone_id)."
# }

# Account-scoped modules also take account_id:
# variable "account_id" {
#   type        = string
#   description = "Cloudflare Account ID."
#   validation {
#     condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
#     error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
#   }
# }

# Prefer list(object) with optional() for repeatable config the operator drives
# from tfvars:
# variable "records" {
#   type = list(object({
#     name    = string
#     enabled = optional(bool, true)
#   }))
#   default     = []
#   description = "..."
# }
