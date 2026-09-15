terraform {
  required_version = "~> 1.16.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.106.0" // https://registry.terraform.io/providers/bpg/proxmox/latest
    }
  }

  # State lives in the founder's own `loady-vm` Azure subscription, not on this disk. It holds the
  # Proxmox password in clear, so the account has shared key access disabled: the only way in is an
  # Entra identity holding Storage Blob Data Owner, which `az login` supplies. Blob versioning and
  # 30 day soft delete make a bad apply recoverable.
  # docs/manual-secrets.md owns the recovery. These are identifiers, not secrets.
  backend "azurerm" {
    use_azuread_auth     = true
    tenant_id            = "385bd049-aaa0-4d85-9bd8-d777e354c0a7"
    subscription_id      = "d17722fc-3eb6-42ac-a074-5a43602cf703"
    resource_group_name  = "rg-loady-tfstate"
    storage_account_name = "stloadytfstate"
    container_name       = "infra"
    key                  = "terraform.tfstate"
  }
}
