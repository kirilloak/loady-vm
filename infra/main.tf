# The Loady development workstation: one Ubuntu Server VM on the Proxmox host, built from the cloud
# image. Proxmox's cloud-init drive does the one thing an image cannot — a user with a key and a
# static address — and bootstrap.sh does everything else, run here as a post step over SSH on every
# apply. docs/remote-development.md owns the architecture; this root owns the machine.

locals {
  ssh_public_key = var.ssh_public_key != null ? var.ssh_public_key : trimspace(
    file(pathexpand("~/.ssh/id_ed25519.pub"))
  )
  ipv4_address   = split("/", var.ipv4_cidr)[0]
  bootstrap_path = "${path.module}/bootstrap.sh"
  runner_path    = "${path.module}/run-bootstrap.sh"
}

resource "proxmox_download_file" "ubuntu_cloud_image" {
  # A failed or state-less earlier run can leave this exact file in Proxmox without Terraform
  # owning it. Replace only that colliding filename with the image configured below, then manage it.
  datastore_id        = var.datastore_images
  node_name           = var.node_name
  content_type        = "iso"
  file_name           = basename(var.ubuntu_image_url)
  url                 = var.ubuntu_image_url
  upload_timeout      = 1800
  overwrite_unmanaged = true
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
  # host reboot must not bring both up. vm-loady is what starts this one, and it shuts the other
  # one down first.

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

  # First, because this one waits: a remote-exec blocks on the connection block above until sshd
  # answers, and a freshly created VM is still booting. Everything after it can assume SSH.
  provisioner "remote-exec" {
    inline = ["install -d -m 700 /home/dev/.cache/loady-bootstrap"]
  }

  provisioner "file" {
    source      = local.bootstrap_path
    destination = "/home/dev/.cache/loady-bootstrap/bootstrap.sh"
  }

  # The bootstrap runs as a systemd unit rather than as a child of this connection, so that losing
  # the channel costs an attach rather than the run. run-bootstrap.sh beside this file owns that.
  provisioner "file" {
    source      = local.runner_path
    destination = "/home/dev/.cache/loady-bootstrap/run-bootstrap.sh"
  }

  # Secrets travel in a 0600 file rather than as process arguments, so they are not visible in the
  # remote command line or in Terraform's output. The base64 round trip keeps multi-line key
  # material intact through the template.
  provisioner "file" {
    content     = <<-EOT
      export LD_SECRET_SSH_GIT_BASE64="$(printf %s '${base64encode(var.loady_ssh_git_base64)}' | base64 -d)"
      export LD_SECRET_SSH_GITHUB_BASE64="$(printf %s '${base64encode(var.github_ssh_base64)}' | base64 -d)"
      export LD_SECRET_GITHUB_TOKEN="$(printf %s '${base64encode(coalesce(var.github_token, " "))}' | base64 -d)"
      export LD_SECRET_ADO_TOKEN="$(printf %s '${base64encode(coalesce(var.azure_devops_token, " "))}' | base64 -d)"
    EOT
    destination = "/home/dev/.cache/loady-bootstrap/environment"
  }

  provisioner "remote-exec" {
    # The runner takes the environment file over to the run's own copy and removes this one, so the
    # keys are off this path as soon as the run starts. Keeping secrets out of the command is what
    # lets Terraform show progress.
    inline = [
      "chmod 600 /home/dev/.cache/loady-bootstrap/environment",
      "bash /home/dev/.cache/loady-bootstrap/run-bootstrap.sh || { status=$?; echo \"Bootstrap failed with status $status; inspect with: ssh loady-vm tail -n 200 ~/.local/state/loady-vm/bootstrap/latest.log\" >&2; exit $status; }",
    ]
  }

  depends_on = [proxmox_virtual_environment_vm.loady_vm]
}
