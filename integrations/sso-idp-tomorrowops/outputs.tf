output "client_id" {
  description = "Client ID to configure on the Loady B2C generic OIDC identity provider."
  value       = azuread_application.oidc.client_id
}

output "client_secret" {
  description = "Client secret to configure on the Loady B2C generic OIDC identity provider."
  value       = azuread_application_password.oidc.value
  sensitive   = true
}

output "metadata_url" {
  description = "OIDC metadata URL to configure on the Loady B2C identity provider."
  value       = "https://login.microsoftonline.com/${var.tenant_id}/v2.0/.well-known/openid-configuration"
}

output "issuer" {
  description = "Expected token issuer for the private Entra tenant."
  value       = "https://login.microsoftonline.com/${var.tenant_id}/v2.0"
}

output "domain_hint" {
  description = "Domain hint to configure in Loady B2C and the Loady SSO configuration document."
  value       = var.domain_hint
}

output "scope" {
  description = "OIDC scopes to configure on the Loady B2C identity provider."
  value       = "openid profile email"
}

output "claims_mapping" {
  description = "Generic OIDC claim mapping to enter in the Loady B2C provider configuration."
  value = {
    user_id      = "sub"
    display_name = "name"
    given_name   = "given_name"
    surname      = "family_name"
    email        = "preferred_username"
  }
}
