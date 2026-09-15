terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.9"
    }
  }

  # State lives in the founder's own `loady-vm` Azure subscription, not on this disk. It holds the
  # OIDC client secret, and any test user password, in clear; the account has shared key access
  # disabled, so an Entra identity holding Storage Blob Data Owner is the only way in.
  # docs/manual-secrets.md owns the recovery. These are identifiers, not secrets.
  backend "azurerm" {
    use_azuread_auth     = true
    tenant_id            = "385bd049-aaa0-4d85-9bd8-d777e354c0a7"
    subscription_id      = "d17722fc-3eb6-42ac-a074-5a43602cf703"
    resource_group_name  = "rg-loady-tfstate"
    storage_account_name = "stloadytfstate"
    container_name       = "sso-idp-tomorrowops"
    key                  = "terraform.tfstate"
  }
}

provider "azuread" {
  tenant_id = var.tenant_id
}
