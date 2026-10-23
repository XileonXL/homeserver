# ansible

Configures the Proxmox host and the LXC containers. OpenTofu creates the guests;
Ansible configures what runs on the host and inside them. Home Assistant OS is an
appliance and is not managed here.

| Role | Applied to | What it does |
|---|---|---|
| `proxmox_domain` | `proxmox` | Sets the DNS domain of the node |
| `tailscale` | `proxmox`, `caddy` | Installs Tailscale and joins the tailnet; the host also advertises the LAN as a subnet router |
| `lxc_tun` | `proxmox` | Gives the Caddy container `/dev/net/tun` (restarts it only when it changes) |
| `tailnet_dns` | `caddy` | dnsmasq on Caddy's Tailscale address, answering the local domain over the tailnet |
| `proxmox_opentofu` | `proxmox` | Creates the API token for OpenTofu and downloads the Debian LXC template |
| `haos_image` | `proxmox` | Downloads the Home Assistant OS disk image for OpenTofu to import |
| `haos_network` | `proxmox` | Sets the static address of Home Assistant OS and the proxies it trusts, through the guest agent |
| `alerts` | `proxmox` | Sends Proxmox notifications and a thin pool warning to Telegram; optional heartbeat to an external watchdog |
| `media_disk` | `proxmox` | Formats an empty media disk, mounts it and bind-mounts it into the `media` container |
| `pihole` | `pihole` | Installs and configures Pi-hole v6 |
| `caddy` | `caddy` | Reverse proxy: every service as `https://<name>` with Caddy's internal CA |
| `gatus` | `gatus` | Builds and runs the Gatus status page; alerts through Telegram |
| `jellyfin` | `media` | Installs Jellyfin from its apt repository and creates the library directories |
| `qbittorrent` | `media` | Installs headless qBittorrent, downloading onto the media disk |
| `flaresolverr` | `media` | Installs FlareSolverr from the release tarball, for indexers behind a browser challenge |
| `jackett` | `media` | Installs Jackett from the release tarball, for sites Prowlarr has no definition for |
| `prowlarr` | `media` | Installs Prowlarr from the release tarball, as a search front end for qBittorrent |
| `bidsenseai_extractor` | `bidsenseai_extractor` | Runs the BidSense AI `doc-extractor` nightly with a Claude Code subscription and IAM Roles Anywhere; see its [README](roles/bidsenseai_extractor/README.md) |

Hosts and addresses are in `inventory/hosts.yml`; per-group settings in
`inventory/group_vars/`.

## Prerequisites

Ansible on the workstation, Tailscale running on it (the host is reached as `pve` and
the containers through it, at home too), and a dedicated SSH key authorised on the host. The
script creates `~/.ssh/id_ed25519_personal_homeserver` if it is missing:

```bash
../scripts/setup-ssh-key.sh <proxmox-address>
```

## Remote access

Everything goes over Tailscale: the host is `pve` and the containers are reached through
it (`ProxyCommand` in `inventory/hosts.yml`), at home too. The first connection to `pve`
trusts its host key (`StrictHostKeyChecking=accept-new`), see
[decisions](../docs/decisions.md#tailscale-also-on-caddy-with-its-own-tiny-dns-for-the-local-domain).

Rebuilding from scratch, before `pve` is on the tailnet: from home, use
`-e ansible_host=<LAN IP>` for the Ansible run and
`-var proxmox_endpoint=https://<LAN IP>:8006/` for OpenTofu.

Tailscale DNS: the `tailscale` role leaves the host's current setting alone. New nodes
join with it off; set `tailscale_accept_dns` to converge an existing one.

The `tailnet_dns` role runs its own dnsmasq unit on Caddy. With `bind-dynamic` dnsmasq
also holds a wildcard socket on port 53, but it only answers queries that arrive on
`tailscale0`; nothing else listens on port 53 there.

## Secrets

Credentials live in `.env` at the repository root (git-ignored, see `.env.example`).
Load it before running anything:

```bash
set -a; source ../.env; set +a
```

| Variable | Set by | Needed |
|---|---|---|
| `PROXMOX_VE_API_TOKEN` | the `proxmox_opentofu` role | by OpenTofu |
| `TAILSCALE_AUTHKEY` | you | only when a node joins the tailnet; reusable, pre-authorized, short expiry; tagged `tag:homeserver` when Caddy joins, untagged for the host; revoke it after the join |
| `PIHOLE_WEB_PASSWORD` | you | on the first Pi-hole install, or to change the password |
| `TELEGRAM_BOT_TOKEN` | you | by the `alerts` role |
| `TELEGRAM_CHAT_ID` | the `alerts` role | optional; found from the bot's latest message when empty |
| `HEARTBEAT_URL` | you | optional; enables the heartbeat to an external watchdog |
| `MEDIA_DISK` | you | by the `media_disk` role; the `/dev/disk/by-id/` path of the media disk |
| `QBITTORRENT_PASSWORD` | you | on the first qBittorrent install, or to change the password |
| `EXTRACTOR_DEPLOY_KEY_FILE` | you | by `bidsenseai_extractor`; local path of the read-only GitHub deploy key |
| `EXTRACTOR_CERT_FILE`, `EXTRACTOR_KEY_FILE` | you | by `bidsenseai_extractor`; local paths of the Roles Anywhere certificate and key |
| `EXTRACTOR_TRUST_ANCHOR_ARN`, `EXTRACTOR_PROFILE_ARN`, `EXTRACTOR_ROLE_ARN` | you | by `bidsenseai_extractor`; Roles Anywhere ARNs from `tofu output` |
| `EXTRACTOR_DB_CLUSTER_ARN`, `EXTRACTOR_DB_SECRET_ARN`, `EXTRACTOR_DB_NAME`, `EXTRACTOR_DOCUMENTS_BUCKET` | you | by `bidsenseai_extractor`; database and bucket from `tofu output` |
| `CLAUDE_CODE_OAUTH_TOKEN` | you | by `bidsenseai_extractor`; output of `claude setup-token` |

## Run

```bash
ansible-playbook site.yml --limit proxmox --check --diff
ansible-playbook site.yml --limit proxmox
```

A container must exist before its play can run, so the order for a new guest is
(for the Home Assistant VM, only steps 1 and 2 apply):

1. `ansible-playbook site.yml --limit proxmox`
2. Create the guest with [OpenTofu](../opentofu/README.md).
3. `ansible-playbook site.yml --limit proxmox` again: `lxc_tun` adds `/dev/net/tun` to
   Caddy; a running Caddy restarts, so it is unreachable for a few seconds.
4. `ansible-playbook site.yml --limit pihole`
5. `ansible-playbook site.yml --limit caddy` joins Caddy to the tailnet and starts its DNS.
6. Tailscale admin console steps below.

The media stack (Jellyfin and qBittorrent on the `media` container) needs the disk
first:

1. `ansible-playbook site.yml --limit proxmox` formats and mounts the disk.
2. Create the container with [OpenTofu](../opentofu/README.md).
3. `ansible-playbook site.yml --limit proxmox` again attaches the disk to the container.
4. `ansible-playbook site.yml --limit media`
5. `--limit caddy`, `--limit pihole` and `--limit gatus`, to publish and monitor it.

To replace the Telegram bot token, update `.env` and run the `alerts` role with
`-e alerts_rotate_secret=true`.

To replace the OpenTofu API token:

```bash
ansible-playbook site.yml --limit proxmox -e proxmox_opentofu_rotate_token=true
```

## Steps that are not on any machine

- Tailscale admin console: approve the advertised route and disable key expiry for
  the host. Create the tagged auth key, allow `tag:homeserver`, and add split DNS for
  `homeserver.lan` to Caddy's Tailscale address (`tailscale ip -4` in the container); enable "Use Tailscale DNS settings" on the
  laptop. See the [network plan](../docs/02-network-plan.md#caddy-on-the-tailnet).
- Router: hand out the Pi-hole address as the primary DNS server. A secondary must
  filter too; see the [network plan](../docs/02-network-plan.md#dns).
- Every device: install `caddy-root.crt` (written to the repository root by the `caddy`
  play) as a trusted root certificate.
- Telegram: create a bot with @BotFather and send it one message before the first
  run of the `alerts` role.
- Jellyfin web UI: complete the first-run wizard (admin user) and add the `movies` and
  `shows` directories under `/media` as libraries.
- Prowlarr web UI: create the login, add qBittorrent as a download client (host: the
  container's address, the qBittorrent port, its user and password, category `movies`,
  and the options to download in sequential order and first and last pieces first, so
  a film can be watched while it downloads) and add the indexers you want.
