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
| `192.168.1.61` | `gatus` | LXC |
| `192.168.1.62` | `homeassistant` | VM |
| `192.168.1.63` | `media` | LXC |
| `192.168.1.64` | `caddy` | LXC |

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

**A secondary must filter too.**

| Option | Protects against | Cost |
|---|---|---|
| A filtering public resolver, such as AdGuard DNS (`94.140.14.14`) | the server being down | queries that go there skip your own lists and your query log |
| A second Pi-hole on separate hardware | the server being down | another machine; the `pihole` role installs it as is |
| A second Pi-hole in another container | a Pi-hole failure only | |

Use a filtering public resolver as secondary when other people depend on the network
and nobody may be around to fix it. Leave the secondary empty only if a DNS outage is
something you can always repair on the spot.

## Names and the reverse proxy

Services are reached as `https://<name>.homeserver.lan`, with no port numbers.

- Pi-hole answers those names itself, and every one of them points at the reverse
  proxy, not at the service.
- Caddy terminates HTTPS and forwards each name to the right address and port.
- No public authority issues certificates for an invented domain, so Caddy uses its
  own. Its root certificate is installed once on each device; until then the browser
  shows a warning and everything still works.
- `homeserver.lan` itself is a static start page (Homer) generated from the same
  list of sites.

SSH and Ansible keep using addresses: a service name leads to the proxy, not to the
machine behind it.

## Remote access with Tailscale

Tailscale runs on the **Proxmox host only**, as a subnet router that advertises the
whole LAN. Guests need no client.

- In a container it would need nesting and `/dev/net/tun`.
- The host stays reachable when guests are down, which is when remote access matters.

After the first run, approve the route in the Tailscale admin console and disable key
expiry for the host. An expired key cuts remote access without warning.

### DNS over the tailnet

In the Tailscale admin console, under DNS, add the Pi-hole address as a nameserver
twice:

- Restricted to the local domain (`homeserver.lan`), so the service names resolve
  away from home.
- Unrestricted, with "Override DNS servers" enabled, so ads are filtered on your
  devices wherever they are.

Do this only once Pi-hole has been stable for a while. If Pi-hole is down, devices on
the tailnet cannot resolve anything.

The fallback is manual: turn Tailscale off on the device, and DNS goes back to
whatever the local network provides. That is acceptable when the tailnet has one
user who knows why it broke. It is not acceptable if other people depend on it; give
them a filtering secondary instead.

Clients that arrive through the subnet router are source-NATed to the host's address,
so Pi-hole sees them as local and its `LOCAL` listening mode is enough.

## Monitoring

Alerts go to a Telegram chat through a bot. Three things send them:

- Proxmox itself, for failed backups and other system notifications.
- A timer on the host, when the guest storage pool passes 80%.
- Gatus, when a service stops answering. It checks each service directly, not through
  the proxy, so a proxy failure is told apart from a service failure.

None of them can report that the whole machine is down, because they all run on it.
For that the host pings an external dead-man's-switch URL on a timer, and that
service raises the alarm when the pings stop.
