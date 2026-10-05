# ansible

Configures the Proxmox host and the LXC containers. Terraform creates the guests;
Ansible configures what runs on the host and inside them. Home Assistant OS is an
appliance and is not managed here.

| Role | Applied to | What it does |
|---|---|---|
| `tailscale` | `proxmox` | Installs Tailscale; advertises the LAN as a subnet router |
| `proxmox_terraform` | `proxmox` | Creates the API token for Terraform and downloads the Debian LXC template |
| `pihole` | `pihole` | Installs and configures Pi-hole v6 |

Hosts and addresses are in `inventory/hosts.yml`; per-group settings in
`inventory/group_vars/`.

## Prerequisites

Ansible on the workstation, and a dedicated SSH key authorised on the host:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_personal_homeserver -C personal_homeserver
ssh-copy-id -i ~/.ssh/id_ed25519_personal_homeserver.pub root@<proxmox-address>
```

## Secrets

Credentials live in `.env` at the repository root (git-ignored, see `.env.example`).
Load it before running anything:

```bash
set -a; source ../.env; set +a
```

| Variable | Set by | Needed |
|---|---|---|
| `PROXMOX_VE_API_TOKEN` | the `proxmox_terraform` role | by Terraform |
| `TAILSCALE_AUTHKEY` | you | only when a node joins the tailnet |
| `PIHOLE_WEB_PASSWORD` | you | on the first Pi-hole install, or to change the password |

## Run

```bash
ansible-playbook site.yml --limit proxmox --check --diff
ansible-playbook site.yml --limit proxmox
```

A container must exist before its play can run, so the order for a new guest is:

1. `ansible-playbook site.yml --limit proxmox`
2. Create the container with [Terraform](../terraform/README.md).
3. `ansible-playbook site.yml --limit pihole`

To replace the Terraform API token:

```bash
ansible-playbook site.yml --limit proxmox -e proxmox_terraform_rotate_token=true
```

## Steps that are not on any machine

- Tailscale admin console: approve the advertised route and disable key expiry for
  the host.
- Router: hand out the Pi-hole address as the only DNS server, with no secondary. See the
  [network plan](../docs/02-network-plan.md#dns).
