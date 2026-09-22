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
