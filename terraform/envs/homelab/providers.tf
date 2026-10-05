provider "proxmox" {
  endpoint = var.proxmox_endpoint
  # The API token is read from the PROXMOX_VE_API_TOKEN environment variable.

  # The node uses a self-signed certificate and is reachable on the LAN only.
  insecure = true
}
