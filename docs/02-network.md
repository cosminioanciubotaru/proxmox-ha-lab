# Network Design

## VPC
- Name: pve-net, custom subnet mode
- Subnet: pve-subnet, 10.10.0.0/24, europe-west3
- Default VPC deliberately unused: it auto-creates subnets in ~40 regions and permits SSH from 0.0.0.0/0

## Firewall (default is deny-all ingress; these are the only exceptions)
- pve-allow-internal: tcp,udp,icmp from 10.10.0.0/24 - Corosync, Ceph, migration, cluster sync
- pve-allow-iap-ssh: tcp:22 from 35.235.240.0/20 (Google IAP forwarding range) only
- No rule for 8006/8007: Proxmox and PBS web UIs are reachable only via IAP port-forward to localhost

## Internet access
- No external IPs on any VM
- Outbound via Cloud NAT (pve-router / pve-nat, auto-allocated IP) for Debian and Proxmox package downloads
- NAT is structurally outbound-only: inbound packets match no translation entry and are dropped
- Inbound admin access via IAP tunnel, authenticated against the Google account
