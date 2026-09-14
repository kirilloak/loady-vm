variable "virtual_environment_endpoint" {
  type    = string
  default = "https://192.168.1.22:8006"
}

variable "virtual_environment_username" {
  type    = string
  default = "root@pam"
}

variable "virtual_environment_password" {
  type      = string
  sensitive = true # root@pam; loaded from Bitwarden by ld-tfin, never stored here
}

variable "node_name" {
  type    = string
  default = "pve-2"
}

variable "datastore_images" {
  description = "Datastore that holds the downloaded cloud image"
  type        = string
  default     = "local"
}

variable "datastore_disks" {
  description = "NVMe-backed datastore for the VM disk and the cloud-init drive"
  type        = string
  default     = "local-zfs"
}

variable "vm_id" {
  description = "Free id on the node; 200 belongs to the other workstation VM"
  type        = number
  default     = 201
}

variable "vm_name" {
  description = "VM name, hostname and MagicDNS name at once"
  type        = string
  default     = "loady-vm"
}

variable "bridge" {
  description = "Bridge on the home LAN; the Mac reaches the VM directly, no VLAN"
  type        = string
  default     = "vmbr0"
}

variable "ipv4_cidr" {
  description = "Static address on the home LAN, outside the router's DHCP pool. The Mac's /etc/hosts entry resolves to it, and the bootstrap connects to it before any agent exists"
  type        = string
  default     = "192.168.1.51/24"
}

variable "ipv4_gateway" {
  type    = string
  default = "192.168.1.1"
}

variable "cores" {
  description = "Every thread on the node; only one workstation VM runs at a time"
  type        = number
  default     = 16
}

variable "memory_mb" {
  description = "Dedicated, no balloon: a squeezed guest OOM-kills its own build"
  type        = number
  default     = 32768
}

variable "disk_gb" {
  description = "Thin-provisioned on local-zfs: solution, NuGet, node_modules, SQL and Cosmos data"
  type        = number
  default     = 500
}

variable "ubuntu_image_url" {
  description = "Ubuntu Server cloud image, ext4 root grown to the disk by cloud-init on first boot. The codename must be one packages.microsoft.com/repos/azure-cli publishes, or the bootstrap cannot install az; checked 2026-09-14 for resolute"
  type        = string
  default     = "https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-amd64.img"
}

variable "ssh_public_key" {
  description = "OpenSSH public key for the dev user; defaults to the Mac's existing main key, ~/.ssh/id_ed25519.pub. Only the public half reaches the VM, so reusing an existing key costs nothing"
  type        = string
  default     = null
}

variable "ssh_private_key_file" {
  description = "Private half of ssh_public_key, used only to run the bootstrap; null means ssh-agent"
  type        = string
  default     = null
}

# The keys the VM needs to reach its two git remotes, as single-line base64 of each private key
# file. ld-tfin loads them from Bitwarden through .tf-vars and the bootstrap writes them onto the
# VM, so a rebuilt machine clones both repositories without a file being copied by hand. Both are
# required because a successful apply promises a cloned, built and warmed development workstation.

variable "loady_ssh_git_base64" {
  description = "The founder's existing Loady key (~/.ssh/loady/id_rsa on the Mac) with its passphrase removed, for the loady-one checkout. Azure DevOps is the one remote it reaches, where it is already registered. RSA because Azure DevOps accepts nothing else; passphrase-less because a headless Rider backend and an agent shell cannot answer a prompt"
  type        = string
  sensitive   = true

  validation {
    condition     = trimspace(var.loady_ssh_git_base64) != ""
    error_message = "loady_ssh_git_base64 must contain the base64-encoded Git private key."
  }
}

variable "github_ssh_base64" {
  description = "The dev-vm-github key (~/.ssh/kirilloak/dev-vm-github/id_ed25519 on the VM) with its passphrase removed, for the loady-vm checkout. A user key on the founder's own GitHub account, shared with that VM, so a rotation is both machines"
  type        = string
  sensitive   = true

  validation {
    condition     = trimspace(var.github_ssh_base64) != ""
    error_message = "github_ssh_base64 must contain the base64-encoded GitHub private key."
  }
}

variable "github_token" {
  description = "The founder's classic PAT, shared with the kirilloak dev VM. Read-only API use here: pinning GitHub's SSH host keys from api.github.com/meta, and GH_TOKEN for agents. Optional, because everything it does degrades to a warning"
  type        = string
  sensitive   = true
  default     = null
}
