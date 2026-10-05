# homeserver

Infrastructure as code for a single-node home server on Proxmox VE: network-wide ad
filtering, remote access to the LAN, and home automation.

It runs on any x86 machine with virtualization support and a wired network port: a
mini PC, an old desktop, or a laptop with the lid closed. Every address is a setting
you can change.

## What you get

| Service | Runs as | Default address | Purpose |
|---|---|---|---|
| Proxmox VE 9 | host | `192.168.1.50` | hypervisor |
| Tailscale | on the host | | reach the whole LAN from anywhere |
| Pi-hole | LXC | `192.168.1.60` | ad filtering and DNS for the LAN |

Planned: Home Assistant OS, Uptime Kuma, backups, and a Jellyfin media library.

## How it is organised

```
bootstrap/   one script, run once on the host right after installing Proxmox
ansible/     configures the host and everything inside the containers
terraform/   creates the containers and VMs
docs/        install guide, network plan and the reasoning behind each decision
```

Nothing is configured by hand on the machines.

## Requirements

- A machine for Proxmox VE with VT-x and wired Ethernet. Wi-Fi cannot be bridged.
- A workstation with Ansible, Terraform and an SSH client.
- A free [Tailscale](https://tailscale.com) account.

## Adapt it to your network

The defaults assume a `192.168.1.0/24` LAN with the router at `192.168.1.1`.

| Setting | Where |
|---|---|
| Host address, SSH key | `ansible/inventory/hosts.yml` |
| LAN range advertised over Tailscale | `ansible/inventory/group_vars/proxmox.yml` |
| Proxmox endpoint, node name, gateway, container addresses and sizes | `terraform/envs/homelab/variables.tf` |
| Upstream DNS servers for Pi-hole | `ansible/roles/pihole/defaults/main.yml` |

## Getting started

1. **Install Proxmox VE 9** on the machine with a static address outside your
   router's DHCP pool. See [docs/01](docs/01-proxmox-install.md).

2. **Prepare the host.** Details in [bootstrap/](bootstrap/README.md).

   ```bash
   scp -r bootstrap root@192.168.1.50:/root/
   ssh root@192.168.1.50 /root/bootstrap/post-install.sh
   ssh root@192.168.1.50 reboot
   ```

3. **Give Ansible access** with a dedicated SSH key, and create your secrets file.

   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_personal_homeserver
   ssh-copy-id -i ~/.ssh/id_ed25519_personal_homeserver.pub root@192.168.1.50
   cp .env.example .env && chmod 600 .env
   ```

   Put a Tailscale auth key and a password for the Pi-hole web UI in `.env`.

4. **Configure the host.** This joins it to your tailnet as a subnet router and
   creates the API token that Terraform uses.

   ```bash
   set -a; source .env; set +a
   cd ansible
   ansible-playbook site.yml --limit proxmox
   ```

   In the Tailscale admin console, approve the advertised route and disable key
   expiry for the host.

5. **Create the Pi-hole container.**

   ```bash
   set -a; source .env; set +a
   cd terraform/envs/homelab
   terraform init
   terraform plan
   terraform apply
   ```

6. **Install Pi-hole.**

   ```bash
   cd ansible
   ansible-playbook site.yml --limit pihole
   ```

7. **Point your router at it.** Set the Pi-hole address as the only DNS server handed
   out by DHCP. Do not add a secondary: see [docs/02](docs/02-network-plan.md#dns).

More detail in [ansible/](ansible/README.md) and [terraform/](terraform/README.md).

## Documentation

- [Proxmox installation](docs/01-proxmox-install.md)
- [Network plan](docs/02-network-plan.md)
- [Decisions](docs/decisions.md)

## License

[MIT](LICENSE)
