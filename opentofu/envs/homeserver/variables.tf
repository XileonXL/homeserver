variable "proxmox_endpoint" {
  description = "Proxmox VE API endpoint URL"
  type        = string
  default     = "https://192.168.1.50:8006/"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key authorized for root in the containers"
  type        = string
  default     = "~/.ssh/id_ed25519_personal_homeserver.pub"
}

variable "lxc_template_file_id" {
  description = "Proxmox file ID of the Debian LXC template, for example local:vztmpl/debian-13-standard_<ver>_amd64.tar.zst (written by Ansible to lxc_template.auto.tfvars.json)"
  type        = string
}

variable "node_name" {
  description = "Name of the Proxmox node the guests are created on"
  type        = string
  default     = "pve"
}

variable "gateway" {
  description = "LAN gateway, also used as the resolver of each container"
  type        = string
  default     = "192.168.1.1"
}

variable "prefix_length" {
  description = "Prefix length of the LAN"
  type        = number
  default     = 24
}

variable "containers" {
  description = "LXC containers to create, keyed by hostname. Convention: vm_id is 100 plus the last octet of the IP"
  type = map(object({
    vm_id  = number
    ip     = string
    cores  = number
    memory = number
    swap   = number
    disk   = number
  }))
  default = {
    pihole = {
      vm_id  = 160
      ip     = "192.168.1.60"
      cores  = 1
      memory = 512
      swap   = 512
      disk   = 8
    }
    caddy = {
      vm_id  = 164
      ip     = "192.168.1.64"
      cores  = 1
      memory = 256
      swap   = 256
      disk   = 4
    }
    gatus = {
      vm_id  = 161
      ip     = "192.168.1.61"
      cores  = 1
      memory = 1024
      swap   = 512
      disk   = 8
    }
    media = {
      vm_id  = 163
      ip     = "192.168.1.63"
      cores  = 2
      memory = 2048
      swap   = 512
      disk   = 16
    }
  }
}

variable "haos_image_file_id" {
  description = "Proxmox file ID of the Home Assistant OS qcow2 image, for example local:import/haos_ova-<ver>.qcow2 (written by Ansible to haos_image.auto.tfvars.json)"
  type        = string
}

variable "homeassistant" {
  description = "Home Assistant OS virtual machine. memory is in MB, disk in GB"
  type = object({
    vm_id  = number
    cores  = number
    memory = number
    disk   = number
  })
  default = {
    vm_id  = 162
    cores  = 4
    memory = 2048
    disk   = 64
  }
}
