# Phase 8: workloads (in progress)

## Web pair for the application-level failover test
Two containers on different nodes serving the same page. Unlike hypervisor HA,
both run simultaneously, so one node can be lost without a restart.

| | web1 | web2 |
|---|---|---|
| CT ID | 110 | 111 |
| Node | pve1 | pve3 |
| Address | 10.20.0.110 | 10.20.0.111 |
| Server | Caddy 2.11.4 | Caddy 2.11.4 |

Created with the network set at creation time (bridge=gnet, gw=10.20.0.1,
mtu=1410), which was not possible for ct:100 because the SDN did not exist yet.

Each response carries a "Served-By" header naming the container. Checking a
header rather than page content makes the failover measurable in a request loop:
the value flips from web1 to web2 at the moment of takeover.

## Notes
- --nameserver 1.1.1.1 instead of inheriting Google's metadata server
  (169.254.169.254). Package downloads were noticeably faster than the 174 kB/s
  observed on ct:100, where name resolution returned IPv6-only records while the
  guest network is IPv4-only.
- The container template lives on each node's LOCAL storage, so it had to be
  downloaded on pve3 as well before ct:111 could be created. Only needed at
  creation time; the container's disk is on Ceph and can run on any node.
- Caddy is not in Debian's repositories: added via its own signed repository,
  the same key/sources/update/install pattern used for Proxmox and gcloud.
- Writing files into a container via pct exec failed when the HTML contained
  "<!DOCTYPE": inside double quotes bash treats ! as history expansion. Fixed
  by using a quoted heredoc piped into "pct exec ... tee".

## Still to do
- keepalived on both containers sharing a virtual IP (10.20.0.50)
- Failover test: kill the node holding the VIP, measure downtime with a
  once-per-second request loop, watch Served-By change
- Vaultwarden, Uptime Kuma

## Application-level redundancy: shared address with keepalived

keepalived inside both containers, sharing 10.20.0.50. Same technique as the
node gateway, one level up: there it moves an address between hosts, here
between containers.

  vrrp_instance WEBVIP, virtual_router_id 61 (the gateway uses 51; two VRRP
  groups on the same network must not share an ID)
  web1 priority 150, web2 priority 130, both state BACKUP, nopreempt

No FAULT state this time, unlike the gateway setup: each container already had
a real address on eth0, which VRRP needs as the source for its announcements.

## Making it visible in a browser
The guest network 10.20.0.0/24 is not reachable from outside, so a port forward
was added on pve2 (deliberately neither web container's node):

  iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to 10.20.0.50:80
  iptables -t nat -A OUTPUT -p tcp -d 10.10.0.3 --dport 8080 -j DNAT --to 10.20.0.50:80
  iptables -t nat -A POSTROUTING -p tcp -d 10.20.0.50 --dport 80 -j MASQUERADE

The MASQUERADE rule was the piece initially missing: without it the forward
returned nothing at all. The web container replied directly to the original
source address, and pve2 discarded the reply because it did not match the
connection it had opened. Rewriting the source makes the reply return the same
way it went out. This is the standard companion to DNAT when the forwarding
host is not the target's default gateway.

Firewall rule pve-allow-iap-demo added for tcp:8080 from 35.235.240.0/20.
Access: gcloud compute start-iap-tunnel pve2 8080 --local-host-port=localhost:8080
then http://localhost:8080 in the browser.

These forward rules are temporary and not persisted; they exist for the demo.

## Failover test: web service
Request loop once per second against 10.20.0.50, printing which container
answered. pve1 (holding both web1 and the VIP) was powered off.

  19:01:13 web1
  19:01:14 web1     <- last request served by web1
  19:01:15 web2     <- first request served by web2
  19:01:16 web2

No failed request. The changeover completed within one second, and the browser
showed the page served by web2 on refresh while pve1 stayed powered off.

## The distinction this demonstrates
Hypervisor HA RESTARTS a service after a node fails (~30 s in the phase 6 test).
Application redundancy means the service never stopped: the second instance was
already running and simply started receiving the traffic. Both belong in a real
design - HA covers services that cannot be clustered, redundancy covers those
that can.

## Four failover types now measured
  container after node loss   HA restart              ~30 s
  running VM, planned move    live migration          30 ms
  gateway after node loss     VRRP address takeover   < 1 s, 0 packets lost
  web service after node loss two instances + VRRP    < 1 s, 0 failed requests
