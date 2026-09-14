variable "tenant_id" {
  description = "Microsoft Entra tenant ID in which to create the test identity provider application."
  type        = string
  nullable    = false
}

variable "application_display_name" {
  description = "Display name of the confidential OIDC application used by Loady B2C."
  type        = string
  default     = "Loady SSO test identity provider"
  nullable    = false
}

variable "b2c_callback_url" {
  description = "Loady B2C generic OIDC callback URL ending in /oauth2/authresp."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^https://[^/]+/.+/oauth2/authresp$", var.b2c_callback_url))
    error_message = "b2c_callback_url must be an HTTPS Azure B2C /oauth2/authresp URL."
  }
}

variable "client_secret_end_date" {
  description = "Stable RFC3339 expiry of the OIDC client secret."
  type        = string
  nullable    = false

  validation {
    condition     = can(formatdate("YYYY-MM-DD'T'hh:mm:ssZ", var.client_secret_end_date))
    error_message = "client_secret_end_date must be a valid RFC3339 timestamp."
  }
}

variable "domain_hint" {
  description = "Domain hint configured on the corresponding Loady B2C identity provider."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.domain_hint)) > 0
    error_message = "domain_hint must not be empty."
  }
}

variable "test_users" {
  description = "Optional test users keyed by user principal name. Passwords remain in local Terraform state."
  type = map(object({
    display_name          = string
    password              = string
    force_password_change = optional(bool, false)
  }))
  default   = {}
  sensitive = true
}
