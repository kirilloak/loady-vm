# The Loady development workstation: one Ubuntu Server VM on the Proxmox host, built from the cloud
# image. Proxmox's cloud-init drive does the one thing an image cannot — a user with a key and a
# static address — and bootstrap.sh does everything else, run here as a post step over SSH on every
# apply. docs/remote-development.md owns the architecture; this root owns the machine.

locals {
  ssh_public_key = var.ssh_public_key != null ? var.ssh_public_key : trimspace(
    file(pathexpand("~/.ssh/loady/loady-vm/id_ed25519.pub"))
  )
  ipv4_address       = split("/", var.ipv4_cidr)[0]
  bootstrap_path     = "${path.module}/bootstrap.sh"
  tailscale_api_path = "${path.module}/tailscale-api.sh"
}

resource "proxmox_download_file" "ubuntu_cloud_image" {
  datastore_id   = var.datastore_images
  node_name      = var.node_name
  content_type   = "iso"
  file_name      = basename(var.ubuntu_image_url)
  url            = var.ubuntu_image_url
  upload_timeout = 1800
}

resource "proxmox_virtual_environment_vm" "loady_vm" {
  name            = var.vm_name
  description     = "Loady development workstation — docs/remote-development.md in the loady-vm repository"
  node_name       = var.node_name
  vm_id           = var.vm_id
  machine         = "q35"
  scsi_hardware   = "virtio-scsi-single"
  on_boot         = false
  stop_on_destroy = true
  boot_order      = ["scsi0"]

  # on_boot is false on purpose, unlike a server: only one workstation VM may run at a time, and a
  # host reboot must not bring both up. ld-up is what starts this one, and it refuses while the
  # other is running.

  # No guest agent: the provider would wait for it to report an address, the cloud image has none,
  # and attaching one later costs a cold restart. Ubuntu shuts down cleanly on ACPI without it.
  agent {
    enabled = false
  }

  # `units` is the CFS weight against the cluster guests on the same threads (default 1024): a
  # build here wins contention two to one rather than sharing evenly with idle nodes.
  cpu {
    cores = var.cores
    type  = "host"
    units = 2048
  }

  # No balloon (floating defaults to 0): the host must never shrink this VM under pressure, because
  # a squeezed guest OOM-kills its own build. Without a balloon or agent the Proxmox summary shows
  # QEMU's resident size, which reaches 100% once the guest page cache has touched every page and
  # never comes back down; that is expected, not a leak.
  memory {
    dedicated = var.memory_mb
  }

  operating_system {
    type = "l26"
  }

  disk {
    datastore_id = var.datastore_disks
    file_id      = proxmox_download_file.ubuntu_cloud_image.id
    interface    = "scsi0"
    file_format  = "raw"
    iothread     = true
    ssd          = true
    discard      = "on"
    size         = var.disk_gb
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  serial_device {}

  vga {
    type = "serial0"
  }

  initialization {
    datastore_id = var.datastore_disks
    # Proxmox would otherwise run a package upgrade on first boot, holding the apt lock exactly
    # while the post step starts the bootstrap, which does the upgrade itself.
    upgrade = false

    user_account {
      username = "dev"
      keys     = [local.ssh_public_key]
    }

    ip_config {
      ipv4 {
        address = var.ipv4_cidr
        gateway = var.ipv4_gateway
      }
    }
  }

  lifecycle {
    # The image is consumed once at creation; a newer download must not replace the disk.
    ignore_changes = [disk[0].file_id]
  }

  # Orders the Tailscale cleanup after the VM on destroy; see terraform_data.tailscale_device.
  depends_on = [terraform_data.tailscale_device]
}

# One single-use, short-lived key so the bootstrap joins the tailnet without a browser. It is the
# founder's key, so the VM lands as one of the founder's devices; it is minted minutes before it is
# used and dead an hour later. `always` re-mints it once spent, so every apply carries a live key
# and the bootstrap can rejoin after a node-key expiry or a rebuild without a browser either.
resource "tailscale_tailnet_key" "loady_vm" {
  reusable            = false
  ephemeral           = false
  preauthorized       = true
  expiry              = 3600
  description         = "loady-vm ${var.vm_name}"
  recreate_if_invalid = "always"

  lifecycle {
    replace_triggered_by = [proxmox_virtual_environment_vm.loady_vm.id]
  }
}

# `tailscale up` creates a member device outside Terraform's resource model. Delete exact-hostname
# matches before the VM exists to clean older residue, and again on destroy so a disposable VM does
# not leave a stale device behind and its replacement gets the canonical name. The VM depends on
# this resource rather than the reverse, so on destroy the device is removed only after the VM has
# been shut down and deleted: a node still online when its registration is deleted re-registers,
# which is how the next one ends up named loady-vm-1 and every `ssh loady-vm-ts` reaches nothing.
resource "terraform_data" "tailscale_device" {
  input = {
    hostname    = var.vm_name
    script_path = abspath(local.tailscale_api_path)
  }

  provisioner "local-exec" {
    command = self.input.script_path
    environment = {
      LD_TAILSCALE_HOSTNAME = self.input.hostname
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = self.input.script_path
    environment = {
      LD_TAILSCALE_HOSTNAME = self.input.hostname
    }
  }
}

# Runs the bootstrap on every apply: the script converges and upgrades, so an apply is also the
# VM's update, and the plan always shows this one resource replaced. Between applies, setup.sh
# beside this file runs the same script the same way, without Terraform.
resource "terraform_data" "bootstrap" {
  triggers_replace = [
    proxmox_virtual_environment_vm.loady_vm.id,
    timestamp(),
  ]

  connection {
    type        = "ssh"
    host        = local.ipv4_address
    user        = "dev"
    private_key = var.ssh_private_key_file != null ? file(pathexpand(var.ssh_private_key_file)) : null
    agent       = var.ssh_private_key_file == null
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = ["install -d -m 700 /home/dev/.cache/loady-bootstrap"]
  }

  provisioner "file" {
    source      = local.bootstrap_path
    destination = "/home/dev/.cache/loady-bootstrap/bootstrap.sh"
  }

  # Secrets travel in a 0600 file rather than as process arguments, so they are not visible in the
  # remote command line or in Terraform's output. The base64 round trip keeps multi-line key
  # material intact through the template.
  provisioner "file" {
    content     = <<-EOT
      export TS_AUTHKEY="$(printf %s '${base64encode(tailscale_tailnet_key.loady_vm.key)}' | base64 -d)"
      export LD_SECRET_SSH_ADO_BASE64="$(printf %s '${base64encode(coalesce(var.loady_ssh_ado_base64, " "))}' | base64 -d)"
      export LD_SECRET_SSH_GITHUB_BASE64="$(printf %s '${base64encode(coalesce(var.loady_ssh_github_base64, " "))}' | base64 -d)"
    EOT
    destination = "/home/dev/.cache/loady-bootstrap/environment"
  }

  provisioner "remote-exec" {
    # The environment file exists only for this run, is readable only by dev, and is removed on
    # either outcome. Keeping secrets out of the command is what lets Terraform show progress.
    inline = [
      "chmod 600 /home/dev/.cache/loady-bootstrap/environment",
      "trap 'rm -f /home/dev/.cache/loady-bootstrap/bootstrap.sh /home/dev/.cache/loady-bootstrap/environment; rmdir /home/dev/.cache/loady-bootstrap 2>/dev/null || true' EXIT; set -a; . /home/dev/.cache/loady-bootstrap/environment; set +a; bash /home/dev/.cache/loady-bootstrap/bootstrap.sh || { status=$?; echo \"Bootstrap failed with status $status; inspect with: ssh loady-vm tail -n 200 ~/.local/state/loady-vm/bootstrap/latest.log\" >&2; exit $status; }",
    ]
  }

  depends_on = [proxmox_virtual_environment_vm.loady_vm, terraform_data.tailscale_device]
}
