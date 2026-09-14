terraform {
  required_version = "~> 1.16.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.106.0" // https://registry.terraform.io/providers/bpg/proxmox/latest
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.29.2"
    }
  }
}

# No backend block: state is local, in this directory, and gitignored. It holds the Proxmox
# password and a Tailscale auth key in clear, so it is never committed. A remote backend would mean
# either new ongoing spend or borrowing another project's bucket, and the machine is disposable
# enough that losing the state costs one `terraform import` or one rebuild.
# docs/manual-secrets.md owns the recovery.
