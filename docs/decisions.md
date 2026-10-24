# Decisions

The choices that shape this repository and why they were made. When one changes, edit
it here.

## ext4 with LVM-thin, not ZFS

On a single consumer disk ZFS gives no redundancy: checksums detect corruption but
cannot repair it. Its cache takes several gigabytes of RAM, and it amplifies writes on
consumer flash. LVM-thin provides snapshots and thin provisioning, which is all this
needs. With two or more disks and plenty of RAM the answer would be ZFS.

## Containers for light services, VMs for the rest

An LXC container shares the host kernel, starts in seconds and runs Pi-hole in
512 MB. A VM is for anything that needs its own kernel or ships as an appliance image,
such as Home Assistant OS, and for anything that runs Docker.

## The `bpg/proxmox` OpenTofu provider

It is actively maintained and covers containers, VMs and file downloads. The older
`Telmate/proxmox` provider is not.

## OpenTofu creates, Ansible configures

OpenTofu creates a guest and stops. Everything inside it is Ansible's, so that
changing a setting never requires replacing the guest. Nothing is done by hand on a
machine.

## Local OpenTofu state

One operator and no CI. Remote state would make rebuilding the house depend on a
cloud account. The state is never committed, because it can hold secrets in plaintext.

## Secrets in a git-ignored `.env`

The roles and the provider read credentials from the environment, so they never reach
a tracked file or the OpenTofu state. Where the `.env` values come from is up to
you; a password manager works.

## No unfiltered secondary DNS

A secondary resolver is used alongside the primary, not after it, so an ordinary
public resolver lets ads through even while Pi-hole is up. A secondary is fine as long
as it filters too. See the [network plan](02-network-plan.md#dns).

## Tailscale on the host, as a subnet router

One install gives access to every guest, and it keeps working when the guests are
down. See the [network plan](02-network-plan.md#remote-access-with-tailscale).

## Tailscale also on Caddy, with its own tiny DNS for the local domain

Foreign networks often use `192.168.1.0/24` too, so away from home the LAN addresses
and the subnet route collide and the `.lan` names point at the wrong machine.
Renumbering the home LAN would fix it only until a network with the new range turns up,
and it touches every device and DHCP reservation. Instead Caddy, which every name
resolves to, joins the tailnet with its own stable `100.x` address (a normal client
with kernel networking; it needs `/dev/net/tun`, which only root@pam can set, so the
`lxc_tun` role does it on the host, as it does for the media bind mount).

Names must resolve to that address away from home. A dnsmasq on Caddy listens on the
Tailscale address only and answers `homeserver.lan` and every subdomain with it;
Tailscale split DNS sends just that domain to it. Pi-hole is untouched and stays the
LAN resolver. Names and Caddy's certificates do not change.

Having Pi-hole answer both ways (dnsmasq `localise-queries`) does not work: it picks the
address on the same subnet as the receiving interface, and `tailscale0` is a `/32`, so
nothing matches. Everything else stays off the tailnet: it is reached through Caddy, or
by SSH through the Proxmox host. Ansible and OpenTofu always go over Tailscale, at home
too: they do not auto-detect, because a foreign network that overlaps `192.168.1.x` makes
a reachability check unreliable, and one path is simpler to keep working. Servers do not
accept Tailscale DNS.

The first SSH connection to `pve` trusts its host key (`accept-new`) instead of a pinned
entry: reaching it first requires being on the tailnet, which WireGuard authenticates, and
a pinned key in the repository would be one more value to maintain.

## Bulk data on a separate disk

A full LVM thin pool corrupts guests instead of just refusing writes. Anything that
grows without bound, such as a media library, lives on its own disk, never on
`local-lvm`. Alert on thin pool usage well before it fills.

## No Kubernetes, no metrics stack

A single node gains nothing from an orchestrator, and the services a house depends on
should not share a machine with experiments. Home Assistant shows the few metrics
that matter.

## A reverse proxy with its own certificate authority

Names without ports need a proxy, and the Proxmox interface only speaks HTTPS.
Browsers also withhold features such as the microphone from plain HTTP pages. Caddy
issues certificates from an internal authority because no public one will for a
private domain. Buying a real domain would remove the need to install a root
certificate on each device.

## Alerts through Telegram, not email

A bot needs no mail server, no relay account and no sender reputation, and the
message arrives where it will be read. Proxmox reaches it through a webhook.

## Gatus instead of a click-configured monitor

Gatus is configured entirely from a file, so the checks live in the repository. It is
only published as a container image, and containers here do not run Docker, so the
role builds it from source at a pinned version.

## A static start page

The start page is plain files served by the proxy that already exists. It adds no
service to keep running, and it does not depend on any of the services it links to.

## Media in one container, on its own disk

Jellyfin and the torrent client share one container, so both see the media disk with
the same users and permissions. The disk is formatted and mounted on the host and
bind-mounted into the container; only root on the node can do that, so Ansible does
it and OpenTofu ignores mount points. Nothing on that disk is backed up.

Some indexers sit behind a browser challenge that Prowlarr cannot pass on its own.
FlareSolverr runs next to it for those, listening on the loopback address only
because it has no authentication, and only indexers tagged for it go through it.

Prowlarr's indexer definitions are declarative and cannot handle a site whose download
links need computation. Jackett has code for some of those, so it runs behind Prowlarr,
which reaches each of its indexers as a Torznab feed; searching still happens in one
place. That container resolves names through Pi-hole instead of the gateway, because
the resolver behind a home router may block the sites the indexers search.


## Home Assistant is defined but powered off

There is nothing in the house for it to control yet, so the VM would only hold memory
and cores. `started = false` keeps the VM and its disk, and its name, proxy site and
status check are removed so nothing links to or alerts on a guest that is off. Set
`started = true` and restore those three entries when the first device arrives.

## A temporary BidSense AI extractor outside the house

`bidsenseai-extractor` (vm_id 180, `192.168.1.80`) runs the nightly document extraction of
another project. It is not a service of the house, so it stays out of the consecutive
numbering of the others and is not on the status page. Only its static site
(`bidsenseai.homeserver.lan`, served by [its own container](#bidsense-ai-web-in-its-own-container))
is published by the proxy and the DNS.

It is temporary and does not belong in this repository long term. To remove it, delete its
entry in `opentofu/envs/homeserver/variables.tf`, its group in `ansible/inventory/hosts.yml`,
its play in `ansible/site.yml`, the `bidsenseai_extractor` role, the `EXTRACTOR_*` and
`CLAUDE_CODE_OAUTH_TOKEN` variables in `.env.example` and `ansible/README.md`, its row in
the root `README.md` and this section.

It uses a Claude Code subscription (`EXTRACTOR_PROVIDER=claude-code`) instead of the API
because the volume is small and a flat subscription costs less than per-token billing.
Migrating is `EXTRACTOR_PROVIDER=anthropic` plus an API key, or the Lambda schedule in the
BidSense AI `infra/`; documents already extracted are not extracted again.

AWS access uses IAM Roles Anywhere with a certificate from a self-managed CA, so no
long-lived access key lives on the machine. Credentials last an hour and the certificate
alone can be revoked.

## HireSignal AI outside the house

`hiresignalai` (vm_id 185, `192.168.1.85`) runs the daily job search and the Telegram bot of
another project. Like the extractor it is not a service of the house, so it stays out of the
consecutive numbering and neither the status page nor the DNS and proxy include it.

It runs here and not on AWS because the Claude Code subscription runs here and the volume is
tiny: one daily run and a bot that mostly waits. The database (`data/jobs.db`) stays in git.
This guest is its only writer, through a deploy key with write access, so there is no merge
to resolve. The Telegram bot uses long polling, so nothing is exposed and no proxy entry or
port is needed. Its Telegram bot is separate from the house alerts bot; failures of its units
still reach the alerts channel.

Accepted risk: the deploy key has write access to the code repository, so it can push code to
`main`, and the next deploy runs it. This is mitigated by Claude running without tools, the
service only committing `data/jobs.db`, and reviews on the Mac. The cleaner alternative, a
separate data repository so the code key can be read-only, is the path if the project grows.

To remove it, delete its entry in `opentofu/envs/homeserver/variables.tf`, its group in
`ansible/inventory/hosts.yml`, its play in `ansible/site.yml`, the `hiresignalai` role, the
`HIRESIGNALAI_*` variables in `.env.example` and `ansible/README.md`, its row in the root
`README.md` and this section, and delete the deploy key in the repository settings.

## BidSense AI web in its own container

`bidsenseai-web` (vm_id 181, `192.168.1.81`, 1 core, 256 MB, 4 GB) only serves the static
BidSense AI site with nginx. The extractor builds the site (Astro, Node.js) and uploads it.

Why a separate guest: the extractor holds a Claude Code token, an AWS certificate and
database access, and runs a build that pulls npm dependencies. A web server on that machine
would put an internet-facing process next to those credentials. The web guest has none of
them and no outbound need, so a flaw in nginx or in the site exposes only public files.

Deploy mechanism: the extractor has a dedicated SSH key whose public half is installed on the
web guest for the `deploy` user with a forced command and `restrict`. The command allows only
write-only rsync into `releases/` (through `rrsync -wo`) and `switch <timestamp>`, which
checks the release (name format, `index.html`, no symlinks), repoints `current` atomically
and keeps the last 3 releases. A forced command gives a synchronous result, so a failed switch
fails the build unit and raises the Telegram alert; a path unit on the web guest would have
needed alert credentials there. No sudo and no root process is involved; the deploy user
owns only `/srv/bidsenseai-web`.

To remove it, delete its entry in `opentofu/envs/homeserver/variables.tf`, its group in
`ansible/inventory/hosts.yml`, its play in `ansible/site.yml`, the `bidsenseai_web` role, its row in the root
`README.md`, and this section, and revert the web parts of the extractor role.
