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
| Home Assistant OS | VM | `192.168.1.62` | home automation |
| Caddy | LXC | `192.168.1.64` | HTTPS reverse proxy, so services are reached by name with no ports |
| Gatus | LXC | `192.168.1.61` | status page and service checks, with alerts through Telegram |
| Jellyfin, qBittorrent, Prowlarr | LXC | `192.168.1.63` | media library on a dedicated disk, a torrent client that downloads onto it, and a search front end for it |

The host also sends its own alerts to Telegram: Proxmox notifications and a warning
before the guest storage fills up.

Every service has a name under a local domain. `https://homeserver.lan` is a start
page with a link to each one, and `https://status.homeserver.lan` shows which are up.

Planned: backups.

## How it is organised

```
bootstrap/   one script, run once on the host right after installing Proxmox
scripts/     helpers that run on the workstation
ansible/     configures the host and everything inside the containers
opentofu/    creates the containers and VMs
docs/        install guide, network plan and the reasoning behind each decision
```

Nothing is configured by hand on the machines.

## Requirements

- A machine for Proxmox VE with VT-x and wired Ethernet. Wi-Fi cannot be bridged.
- A workstation with Ansible, OpenTofu and an SSH client.
- A free [Tailscale](https://tailscale.com) account.

## Adapt it to your network

The defaults assume a `192.168.1.0/24` LAN with the router at `192.168.1.1`.

| Setting | Where |
|---|---|
| Host address, SSH key | `ansible/inventory/hosts.yml` |
| LAN range advertised over Tailscale | `ansible/inventory/group_vars/proxmox.yml` |
| Proxmox endpoint, node name, gateway, container addresses and sizes | `opentofu/envs/homeserver/variables.tf` |
| Upstream DNS servers for Pi-hole | `ansible/roles/pihole/defaults/main.yml` |
| Local DNS names served by Pi-hole | `ansible/inventory/group_vars/pihole.yml` |
| Sites published by the reverse proxy, start page | `ansible/inventory/group_vars/caddy.yml` |
| Service checks | `ansible/inventory/group_vars/gatus.yml` |
| Node domain, Home Assistant address | `ansible/inventory/group_vars/proxmox.yml` |

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
   scripts/setup-ssh-key.sh 192.168.1.50
   cp .env.example .env && chmod 600 .env
   ```

   Fill in `.env`; `.env.example` explains each value.

4. **Configure the host.** This joins it to your tailnet as a subnet router, creates
   the API token that OpenTofu uses, and downloads the container template and the
   Home Assistant OS image.

   ```bash
   set -a; source .env; set +a
   cd ansible
   ansible-playbook site.yml --limit proxmox
   ```

   In the Tailscale admin console, approve the advertised route and disable key
   expiry for the host.

5. **Create the guests:** the containers and the Home Assistant VM.

   ```bash
   set -a; source .env; set +a
   cd opentofu/envs/homeserver
   tofu init
   tofu plan
   tofu apply
   ```

6. **Configure everything inside the guests.**

   ```bash
   set -a; source .env; set +a
   cd ansible
   ansible-playbook site.yml
   ```

7. **Point your router at it.** Set the Pi-hole address as the primary DNS server
   handed out by DHCP. Never add an ordinary public resolver as secondary: see
   [docs/02](docs/02-network-plan.md#dns).

8. **Set up Home Assistant.** Open `http://192.168.1.62` and create your user.

9. **Trust the local certificates.** Install `caddy-root.crt`, which step 6 leaves in
   the repository root, as a trusted root on your devices, then open
   `https://homeserver.lan`.

More detail in [ansible/](ansible/README.md) and [opentofu/](opentofu/README.md).

## Documentation

- [Proxmox installation](docs/01-proxmox-install.md)
- [Network plan](docs/02-network-plan.md)
- [Decisions](docs/decisions.md)

## License

[MIT](LICENSE)
