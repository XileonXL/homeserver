output "container_ipv4" {
  description = "Container name to IPv4 address (without prefix length), for the Ansible inventory"
  value       = { for name, c in var.containers : name => c.ip }
}
