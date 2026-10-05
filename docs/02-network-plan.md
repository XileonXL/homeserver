# Network plan

The defaults assume a `192.168.1.0/24` LAN with the router at `192.168.1.1`. Change
them where the [README](../README.md#adapt-it-to-your-network) says.

## Addresses

Everything here is statically addressed. Keep the static range outside the router's
DHCP pool.

| Address | Host | Type |
|---|---|---|
| `192.168.1.1` | router | gateway, DHCP |
| `192.168.1.50` | `pve` | Proxmox host, Tailscale subnet router |
| `192.168.1.60` | `pihole` | LXC |

Guest IDs are 100 plus the last octet of the address, so Pi-hole is guest 160.

IoT devices stay on DHCP. Home Assistant finds them through mDNS and
protocol-specific discovery, so fixed addresses buy nothing. A device that does need a
stable address gets a DHCP reservation in the router.

## Bridge

Proxmox needs a Linux bridge with a physical NIC as its uplink. The installer writes
this; it is recorded here so it can be restored if `/etc/network/interfaces` breaks.

```
auto vmbr0
iface vmbr0 inet static
    address 192.168.1.50/24
    gateway 192.168.1.1
    bridge-ports <wired-nic>
    bridge-stp off
    bridge-fd 0
```

Wi-Fi cannot be the uplink. An access point drops frames whose source MAC is not the
associated client's, which is what a bridge sends for every guest.

## DNS

Pi-hole becomes the resolver for the LAN, which makes the server a single point of
failure for name resolution.

### A secondary DNS server is not failover

The obvious fix is a public resolver as secondary. It does not work, and it fails
silently.

Operating systems do not treat the list as primary then fallback. They query the
servers opportunistically, often in parallel, and take the first answer. With Pi-hole
as primary and a public resolver as secondary:

| Pi-hole state | What happens |
|---|---|
| Up | some queries go to the public resolver, so ads appear intermittently |
| Down | the internet works, unfiltered, and nobody notices the outage |

Setting it on the router instead of on each device changes nothing.

**A secondary must filter too.** If you need one:

| Option | Protects against |
|---|---|
| A filtering public resolver | the server being down; custom blocklists are lost |
| A second Pi-hole on separate hardware | the server being down |
| A second Pi-hole in another container | a Pi-hole failure only |

The default here is no secondary. On the LAN, the server being down is obvious and is
fixed in place.

## Remote access with Tailscale

Tailscale runs on the **Proxmox host only**, as a subnet router that advertises the
whole LAN. Guests need no client.

- In a container it would need nesting and `/dev/net/tun`.
- The host stays reachable when guests are down, which is when remote access matters.

After the first run, approve the route in the Tailscale admin console and disable key
expiry for the host. An expired key cuts remote access without warning.

### Ad filtering anywhere

Setting the Pi-hole address as a global nameserver for the tailnet, with "Override
DNS" enabled, filters ads on your devices wherever they are.

Do this only once Pi-hole has been stable for a while. If Pi-hole is down, devices on
the tailnet cannot resolve anything.

The fallback is manual: turn Tailscale off on the device, and DNS goes back to
whatever the local network provides. That is acceptable when the tailnet has one
user who knows why it broke. It is not acceptable if other people depend on it; give
them a filtering secondary instead.

Clients that arrive through the subnet router are source-NATed to the host's address,
so Pi-hole sees them as local and its `LOCAL` listening mode is enough.

## Monitoring blind spot

A monitor running on the server cannot report that the server is down. Only an
external check can: a hosted uptime service, or push monitoring from another network.
