provider "proxmox" {
  endpoint = var.virtual_environment_endpoint
  insecure = true

  username = var.virtual_environment_username
  password = var.virtual_environment_password
}

# The founder's personal API key: the VM joins as a member device, so the existing member grants
# cover it without a tag or an ACL change.
provider "tailscale" {
  api_key = var.tailscale_api_key
  tailnet = var.tailscale_tailnet
}
