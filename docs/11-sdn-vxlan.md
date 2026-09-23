# Phase 5: guest networking with SDN / VXLAN (2026-09-22)

## Why a normal bridge cannot work here
GCP's VPC is routed, not switched. Each node sits alone on a /32
(ens4 10.10.0.2/32, default via 10.10.0.1); even node-to-node traffic goes
through Google's router. The router only accepts addresses Google assigned,
so a guest with its own MAC/IP on a bridge would be dropped silently.

Alternative considered: GCP custom routes + IP forwarding on the nodes.
Rejected because routes are static and point to one node, while HA and live
migration move guests between nodes. VXLAN keeps the cloud network unaware
of guest placement, and works identically on physical hardware.

## Node network facts found before changing anything
- NIC is ens4 (not eth0)
- Configured by netplan (/etc/netplan/90-default.yaml): DHCP on any
  interface named en* or eth*
- /etc/network/interfaces (ifupdown2, used by Proxmox) lists ens4 as manual:
  Proxmox never touches the node's own connection
- NAMING RULE: SDN device names must not start with en or eth, or netplan
  would also try to claim them by DHCP
- MTU 1460 on ens4
- /etc/network/interfaces lacked "source /etc/network/interfaces.d/*";
  added on all three nodes (idempotent: only if missing)

## Configuration
- Zone gvxlan: type vxlan, peers 10.10.0.2,10.10.0.3,10.10.0.4, MTU 1410
- VNet gnet: VXLAN tag 10000
- Guest network 10.20.0.0/24 (nodes stay on 10.10.0.0/24)
- MTU 1410 = 1460 (GCP) - 50 (VXLAN header)

Generated per node in /etc/network/interfaces.d/sdn:
  gnet        bridge, single port vxlan_gnet, MTU 1410
  vxlan_gnet  vxlan-id 10000, vxlan_remoteip = the other two nodes

## Staged rollout, and what it did NOT limit
Zone first restricted to pve1 (--nodes pve1), applied, verified, then
extended to all three. Serial console was open during the first apply.
Finding: "pvesh set /cluster/sdn" reloaded network config on ALL nodes,
even though the zone targeted only pve1. The staged rollout limited what
was created, not which nodes reloaded. pve2/pve3 were checked (ens4 intact)
before extending.

## Tests
Guests on different nodes: ct:100 on pve1 (10.20.0.100), vm:101 on pve3
(10.20.0.101).

1. Cross-node ping, VM on pve3 -> container on pve1: 3/3, 0% loss.
   First reply 15.5 ms (ARP broadcast carried through the tunnel), then
   0.4-0.6 ms. ttl=64: no router hop from the guests' point of view, i.e.
   VXLAN rebuilt a switched segment on top of GCP's routed network.
2. MTU boundary, with don't-fragment set:
   -s 1382 (1410-byte packet): 3/3 replies, 0.37 ms
   -s 1383 (1411-byte packet): refused, "Frag needed and DF set (mtu = 1410)"
   The limit sits exactly where the arithmetic predicts.

## Lesson: HA desired state
ct:100 was found stopped after the nodes restarted. It had been stopped with
pct stop at the previous session end; for an HA-managed guest that sets HA's
desired state to "stopped", which HA then enforces across reboots.
Restarted with: ha-manager set ct:100 --state started

## Still to do
Internet access for guests (NAT on the nodes toward Cloud NAT).
The VM's address is set by hand inside Alpine and is lost on reboot.

## Internet access for guests (stage 1: temporary, pve1 only)

Documentation finding: in a VXLAN zone, the subnet's Gateway and SNAT options
have no effect. Per the Proxmox SDN docs, those are deployed only on layer 3
zones (Simple and EVPN); a VXLAN zone assumes an external router exists.
The gateway therefore has to be built by hand.

Two layers of NAT are involved:
  guest 10.20.0.100
    -> node rewrites source to 10.10.0.2   (GCP only accepts assigned addresses)
    -> Cloud NAT rewrites to a public IP   (configured in phase 1)
    -> internet

Temporary configuration on pve1 (not persistent, lost on reboot):
  ip addr add 10.20.0.1/24 dev gnet
  sysctl -w net.ipv4.ip_forward=1
  iptables -t nat -A POSTROUTING -s 10.20.0.0/24 -o ens4 -j MASQUERADE
Container: gw=10.20.0.1 added to net0.

Tests from ct:100:
  ping gateway 10.20.0.1      2/2, 0.04-0.11 ms
  ping 1.1.1.1                3/3, 1.5 ms, ttl=59 (five router hops; compare
                              ttl=64 for the cross-node guest ping, which
                              crosses no router because of the tunnel)
  getent hosts deb.debian.org resolved
  apt-get update              16.9 MB fetched successfully

The apt-get test matters more than the ping: dozens of HTTPS connections moving
real data is precisely the workload that fails when the MTU is wrong.

Observed limitation: throughput was 174 kB/s (16.9 MB in 1m37s), while the node
itself fetches at ~50 MB/s. Name resolution returned IPv6 addresses only while
the guest network is IPv4-only, so per-connection IPv6 timeouts and fallback are
the likely cause. Not investigated further; it does not block the planned
workloads.

Also noted: the container inherited nameserver 169.254.169.254, Google's metadata
server, from the node. It works because the query is masqueraded to the node's
address, but it is a cloud-specific dependency that would not exist on hardware.

## Next: stage 2, make the gateway highly available
A single gateway on pve1 is a single point of failure, which contradicts the
point of the lab. Plan: keepalived on all three nodes sharing 10.20.0.1 as a
virtual IP on gnet, with the NAT rule and ip_forward made persistent. Same
technique as the Caddy pair planned for phase 8.

## Stage 2: highly available gateway with keepalived (VRRP)

A single gateway on one node contradicts the point of the lab, so 10.20.0.1 was
turned into a virtual IP shared by all three nodes.

Design:
- keepalived on every node, vrrp_instance GUESTGW, virtual_router_id 51
- all three configured state BACKUP; priority decides: pve1 150, pve2 140, pve3 130
- advert_int 1: announcements once per second, three missed = holder is gone
- nopreempt: a recovered node does NOT reclaim the address. Reclaiming would
  move the gateway a second time and interrupt traffic for no benefit. Same
  reasoning as HA not moving a guest back after a node returns.
- VRRP announcements travel on gnet, i.e. inside the VXLAN tunnel, so GCP never
  sees them and no cloud firewall rule was needed even though VRRP is neither
  TCP, UDP nor ICMP.

Persistence, one piece per mechanism:
- /etc/network/interfaces.d/gnet-gw: permanent per-node address on gnet
  (pve1 .11, pve2 .12, pve3 .13), written as an alias gnet:0 so ifupdown2 adds
  an address instead of taking over gnet, which SDN manages
- /etc/sysctl.d/99-guest-gateway.conf: net.ipv4.ip_forward=1
- systemd unit guest-nat.service: recreates the MASQUERADE rule at boot,
  using iptables -C || -A so it is safe to run repeatedly

Problem hit: keepalived went straight into FAULT state, "no IPv4 address for
interface". VRRP announcements must be sourced from a real address on the
interface, and the shared address does not count because it may belong to
another node. That is why each node needed its own permanent .11/.12/.13
address in addition to the shared .1.

## Gateway failover test
Setup: ct:100 migrated to pve2 first, so only the gateway would move. Gateway
was on pve1. Ping from inside the container, once per second, with -O so that
missed packets are printed rather than silently skipped.

Result: pve1 powered off. The address appeared on pve2 between two 16-second
polls. The container's ping showed 96 consecutive replies, no missed packets,
0% loss. The outage was shorter than the one-second measurement interval.

Side observation: round-trip time dropped from ~1.75 ms to ~1.12 ms at the
moment of failover. Before, the container on pve2 reached the gateway on pve1
across the tunnel; afterwards the gateway was local, removing one hop.

## Reboot test
pve1 restarted and came back with:
  10.20.0.11 present, 10.20.0.1 absent   (nopreempt honoured)
  net.ipv4.ip_forward = 1                (from the sysctl file)
  MASQUERADE rule present                (recreated by guest-nat.service)
  keepalived and guest-nat both active

## Three kinds of failover now measured
  container after node loss    HA restart              ~30 s
  running VM, planned move     live migration          30 ms
  gateway after node loss      VRRP address takeover   < 1 s, 0 packets lost
