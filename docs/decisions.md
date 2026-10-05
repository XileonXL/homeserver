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

