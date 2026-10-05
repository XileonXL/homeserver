resource "proxmox_virtual_environment_container" "this" {
  for_each = var.containers

  node_name     = var.node_name
  vm_id         = each.value.vm_id
  description   = "Managed by OpenTofu"
  tags          = ["opentofu"]
  unprivileged  = true
  start_on_boot = true
  started       = true

  features {
    # Required by systemd in an unprivileged Debian 13 container.
    nesting = true
  }

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory
    swap      = each.value.swap
  }

  disk {
    datastore_id = "local-lvm"
    size         = each.value.disk
  }

  operating_system {
    template_file_id = var.lxc_template_file_id
    type             = "debian"
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  initialization {
    hostname = each.key

    dns {
      # The gateway, not Pi-hole itself: the container needs a resolver before
      # Pi-hole is installed.
      servers = [var.gateway]
    }

    ip_config {
      ipv4 {
        address = "${each.value.ip}/${var.prefix_length}"
        gateway = var.gateway
      }
    }

    user_account {
      keys = [trimspace(file(pathexpand(var.ssh_public_key_path)))]
    }
  }

  lifecycle {
    # A newer template or a changed key would force replacement of a running
    # container. Both only matter at creation time; later changes are Ansible's job.
    # Bind mounts can only be set by root on the node, so Ansible adds them.
    ignore_changes = [
      operating_system[0].template_file_id,
      initialization[0].user_account,
      mount_point,
    ]
  }
}

resource "proxmox_virtual_environment_vm" "homeassistant" {
  name          = "homeassistant"
  node_name     = var.node_name
  vm_id         = var.homeassistant.vm_id
  description   = "Managed by OpenTofu"
  tags          = ["opentofu"]
  bios          = "ovmf"
  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"
  on_boot       = true
  started       = true

  cpu {
    cores = var.homeassistant.cores
  }

  memory {
    dedicated = var.homeassistant.memory
  }

  agent {
    enabled = true

    # Do not wait for the guest agent to report an address: the API token may not
    # be allowed to query it, and OpenTofu does not manage the guest network.
    wait_for_ip {
      disabled = true
    }
  }

  efi_disk {
    datastore_id      = "local-lvm"
    type              = "4m"
    pre_enrolled_keys = false
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    import_from  = var.haos_image_file_id
    size         = var.homeassistant.disk
    discard      = "on"
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    # The disk holds device pairings and history that cannot be regenerated.
    prevent_destroy = true

    # The image is only used to create the disk; a newer one must not replace the VM.
    ignore_changes = [
      disk[0].import_from,
    ]
  }
}
