variable "account_id" {
  type        = string
  description = "Cloudflare Account ID that owns the DLP profile."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "name" {
  type        = string
  description = "Display name of the custom DLP profile in the Zero Trust dashboard and in Gateway logs. A Gateway policy refers to the profile by UUID, so renaming is an in-place update."

  validation {
    condition     = trimspace(var.name) != "" && trimspace(var.name) == var.name
    error_message = "name must be non-empty and carry no leading or trailing whitespace."
  }
}

variable "description" {
  type        = string
  default     = null
  description = "What the profile is meant to catch. Shown in the dashboard, and the first thing somebody reads when a block they did not expect names this profile."
}

variable "entries" {
  type = list(object({
    name        = string
    regex       = string
    enabled     = optional(bool, true)
    description = optional(string)
    validation  = optional(string)
  }))
  description = <<-EOT
    The detection patterns. The profile matches when any enabled entry does (and
    the match count passes allowed_match_count). Each becomes its own
    cloudflare_zero_trust_dlp_custom_entry attached to the profile, keyed by its
    name lower-cased, so renaming an entry replaces it.

      - `name`        : shown in the dashboard and in the Gateway log line that
                        records a DLP match. Unique within the profile.
      - `regex`       : the pattern. Cloudflare evaluates it with a Rust-style
                        regex engine: no lookaround and no backreferences, the same
                        limits as Terraform's own RE2, so the plan rejects a
                        pattern that does not compile here. That check is best
                        effort - the two engines differ in corners - and the API
                        is the final word.
      - `enabled`     : (Optional) default true. A disabled entry stays in the
                        profile and matches nothing.
      - `description` : (Optional) what the pattern is for.
      - `validation`  : (Optional) "luhn" - additionally require the match to
                        pass a Luhn checksum. For card numbers and other
                        check-digit identifiers it removes most false positives.
                        The provider marks this attribute deprecated and warns on
                        plan when it is set; it still works.

    A pattern that can match an empty string matches every request body, so the
    plan refuses one: `.*`, `[0-9]*` and `(a)?` are all of that shape.
  EOT

  validation {
    condition     = length(var.entries) > 0
    error_message = "entries must contain at least one pattern. A profile with no entries matches nothing, and a policy blocking on it is a control that never fires."
  }

  validation {
    condition     = alltrue([for entry in var.entries : trimspace(entry.name) != "" && trimspace(entry.regex) != ""])
    error_message = "Each entries[*] needs a non-empty name and regex."
  }

  validation {
    condition     = alltrue([for entry in var.entries : entry.validation == null || entry.validation == "luhn"])
    error_message = "entries[*].validation must be \"luhn\" or unset - it is the only check-digit validation Cloudflare offers."
  }
}

variable "allowed_match_count" {
  type        = number
  default     = null
  description = <<-EOT
    How many matches a request body may contain before the profile counts as
    matched. 0 (Cloudflare's default when unset) means a single match triggers
    it. Raising it is how a profile for something that legitimately appears now
    and then - one card number in an order confirmation - is told to fire only on
    a bulk export.
  EOT

  validation {
    condition     = var.allowed_match_count == null || try(var.allowed_match_count >= 0 && var.allowed_match_count <= 1000 && floor(var.allowed_match_count) == var.allowed_match_count, false)
    error_message = "allowed_match_count must be a whole number from 0 to 1000."
  }
}

variable "confidence_threshold" {
  type        = string
  default     = null
  description = "Minimum confidence a match needs before it counts: \"low\", \"medium\", \"high\" or \"very_high\". It applies to entries Cloudflare can score - predefined detections with context or AI validation - and has little effect on a plain custom regex. Unset leaves Cloudflare's default."

  validation {
    condition     = var.confidence_threshold == null || contains(["low", "medium", "high", "very_high"], coalesce(var.confidence_threshold, "low"))
    error_message = "confidence_threshold must be \"low\", \"medium\", \"high\" or \"very_high\" when set."
  }
}

variable "ocr_enabled" {
  type        = bool
  default     = null
  description = "Scan text inside images (screenshots, scanned documents) as well as text content. Catches the screenshot of a spreadsheet; costs scanning time on every image upload. Unset leaves Cloudflare's default."
}

variable "ai_context_enabled" {
  type        = bool
  default     = null
  description = "Let Cloudflare's AI context analysis score matches, to suppress ones whose surroundings show they are not what the pattern looks for. Unset leaves Cloudflare's default."
}
