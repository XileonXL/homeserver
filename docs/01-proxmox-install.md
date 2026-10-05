# Proxmox VE installation

The only manual step. Everything after it is code.

## Firmware settings

| Setting | Value | Notes |
|---|---|---|
| Boot mode | UEFI | not legacy or CSM |
| Secure Boot | Disabled | |
| Virtualization (VT-x or AMD-V) | Enabled | mandatory; without it no VM starts |
| VT-d or AMD-Vi | Enabled if present | only needed for device passthrough |
| Power on after AC loss | Enabled if present | otherwise a power cut leaves the LAN without DNS |

If the machine is a laptop, also set a battery charge limit of 60-80% when the
firmware offers one. A battery held at 100% around the clock swells.

## Installation media

Download the Proxmox VE 9 ISO from the official site and check its SHA256 before
writing it. Write it in raw (DD) mode; tools that copy the ISO as files produce a
drive the installer cannot boot from.

An installer that fails while unpacking a package, always the same one, points to a
bad USB drive rather than to the machine. Write the image with a tool that verifies it
afterwards, or use another drive.

## Storage

Install on **ext4 with LVM-thin**, on the disk that will hold the guests. If the
machine has a second disk for media, leave it untouched. The reasoning is in
[decisions](decisions.md).

| Field | Value | Reason |
|---|---|---|
| Filesystem | `ext4` | |
| `hdsize` | full disk | |
| `swapsize` | `8` | GB |
| `maxroot` | `64` | GB; root only holds the OS, ISOs and templates |
| `minfree` | `16` | GB; LVM-thin needs free extents for metadata |

What remains becomes the `local-lvm` thin pool, where guest disks live.

## Network

Connect Ethernet before starting. Wi-Fi cannot carry a bridge, so the guests would
have no network.

| Field | Value |
|---|---|
| Management interface | the wired NIC |
| Hostname (FQDN) | `pve.home.arpa`, or any name that does not end in `.local` |
| IP address (CIDR) | a static address outside the router's DHCP pool, such as `192.168.1.50/24` |
| Gateway | the router |
| DNS server | the router |

The part of the hostname before the first dot becomes the node name, which OpenTofu
needs (`node_name`, default `pve`). It is awkward to change later.

`.local` is reserved for mDNS, which Home Assistant relies on for discovery.

## After the reboot

Run the [post-install script](../bootstrap/README.md), then check:

```bash
ip -br addr show vmbr0          # the bridge is up and carries the host address
lvs                             # the thin pool exists
grep -c -w vmx /proc/cpuinfo    # one line per CPU thread (svm on AMD)
```

The web UI is at `https://<proxmox-address>:8006`, over HTTPS with a self-signed
certificate.

If the bridge goes down and up under traffic, the cause is the physical link: try
another cable or a direct connection to the router before suspecting the host.
