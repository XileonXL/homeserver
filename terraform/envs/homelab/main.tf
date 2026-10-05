resource "proxmox_virtual_environment_container" "this" {
  for_each = var.containers

  node_name     = var.node_name
  vm_id         = each.value.vm_id
  description   = "Managed by Terraform"
  tags          = ["terraform"]
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
    ignore_changes = [
      operating_system[0].template_file_id,
      initialization[0].user_account,
    ]
  }
}
