# The values below are this root's configuration, not just its interface: there is one tenant, one
# B2C instance and one application, so the defaults are the real thing and the root is reproducible
# from a clean checkout with no untracked file. None of them is a secret — a tenant id, a display
# name, a public callback URL, a date and a domain hint. The secrets this root produces live in
# state, which is remote; see providers.tf.

variable "tenant_id" {
  description = "Microsoft Entra tenant ID in which to create the test identity provider application."
  type        = string
  default     = "385bd049-aaa0-4d85-9bd8-d777e354c0a7"
  nullable    = false
}

variable "application_display_name" {
  description = "Display name of the confidential OIDC application used by Loady B2C."
  type        = string
  default     = "Loady Private SSO Identity Provider"
  nullable    = false
}

variable "b2c_callback_url" {
  description = "Loady B2C generic OIDC callback URL ending in /oauth2/authresp."
  type        = string
  default     = "https://loadyb2cdev.b2clogin.com/loadyb2cdev.onmicrosoft.com/oauth2/authresp"
  nullable    = false

  validation {
    condition     = can(regex("^https://[^/]+/.+/oauth2/authresp$", var.b2c_callback_url))
    error_message = "b2c_callback_url must be an HTTPS Azure B2C /oauth2/authresp URL."
  }
}

variable "client_secret_end_date" {
  description = "Stable RFC3339 expiry of the OIDC client secret."
  type        = string
  default     = "2027-08-14T00:00:00Z"
  nullable    = false

  validation {
    condition     = can(formatdate("YYYY-MM-DD'T'hh:mm:ssZ", var.client_secret_end_date))
    error_message = "client_secret_end_date must be a valid RFC3339 timestamp."
  }
}

variable "domain_hint" {
  description = "Domain hint configured on the corresponding Loady B2C identity provider."
  type        = string
  default     = "tomorrowops"
  nullable    = false

  validation {
    condition     = length(trimspace(var.domain_hint)) > 0
    error_message = "domain_hint must not be empty."
  }
}

variable "test_users" {
  description = "Test users keyed by user principal name. Passwords land in Terraform state and in this default, so treat this file as holding a real (if low-value, test-only) credential once you replace the placeholder password below."
  type = map(object({
    display_name          = string
    given_name            = optional(string)
    surname               = optional(string)
    password              = string
    force_password_change = optional(bool, false)
  }))
  default = {
    "sso@tomorrowops.com" = {
      display_name = "SSO Test User"
      given_name   = "SSO"
      surname      = "Test"
      password     = "REPLACE_ME_BEFORE_APPLYING"
    }
  }
  sensitive = true
}
