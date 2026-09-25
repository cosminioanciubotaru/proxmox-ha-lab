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
