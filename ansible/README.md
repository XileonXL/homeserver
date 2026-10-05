# ansible

Configures the Proxmox host and the LXC containers. OpenTofu creates the guests;
Ansible configures what runs on the host and inside them. Home Assistant OS is an
appliance and is not managed here.

| Role | Applied to | What it does |
|---|---|---|
| `proxmox_domain` | `proxmox` | Sets the DNS domain of the node |
| `tailscale` | `proxmox` | Installs Tailscale; advertises the LAN as a subnet router |
| `proxmox_opentofu` | `proxmox` | Creates the API token for OpenTofu and downloads the Debian LXC template |
| `haos_image` | `proxmox` | Downloads the Home Assistant OS disk image for OpenTofu to import |
| `haos_network` | `proxmox` | Sets the static address of Home Assistant OS and the proxies it trusts, through the guest agent |
| `pihole` | `pihole` | Installs and configures Pi-hole v6 |
| `caddy` | `caddy` | Reverse proxy: every service as `https://<name>` with Caddy's internal CA |

Hosts and addresses are in `inventory/hosts.yml`; per-group settings in
`inventory/group_vars/`.

## Prerequisites

Ansible on the workstation, and a dedicated SSH key authorised on the host. The
script creates `~/.ssh/id_ed25519_personal_homeserver` if it is missing:

```bash
../scripts/setup-ssh-key.sh <proxmox-address>
```

## Secrets

Credentials live in `.env` at the repository root (git-ignored, see `.env.example`).
Load it before running anything:

```bash
set -a; source ../.env; set +a
```

| Variable | Set by | Needed |
|---|---|---|
| `PROXMOX_VE_API_TOKEN` | the `proxmox_opentofu` role | by OpenTofu |
| `TAILSCALE_AUTHKEY` | you | only when a node joins the tailnet |
| `PIHOLE_WEB_PASSWORD` | you | on the first Pi-hole install, or to change the password |

## Run

```bash
ansible-playbook site.yml --limit proxmox --check --diff
ansible-playbook site.yml --limit proxmox
```

A container must exist before its play can run, so the order for a new guest is
(for the Home Assistant VM, only steps 1 and 2 apply):

1. `ansible-playbook site.yml --limit proxmox`
2. Create the guest with [OpenTofu](../opentofu/README.md).
3. `ansible-playbook site.yml --limit pihole`
4. `ansible-playbook site.yml --limit caddy`

To replace the OpenTofu API token:

```bash
ansible-playbook site.yml --limit proxmox -e proxmox_opentofu_rotate_token=true
```

## Steps that are not on any machine

- Tailscale admin console: approve the advertised route and disable key expiry for
  the host.
- Router: hand out the Pi-hole address as the primary DNS server. A secondary must
  filter too; see the [network plan](../docs/02-network-plan.md#dns).
- Every device: install `caddy-root.crt` (written to the repository root by the `caddy`
  play) as a trusted root certificate.
