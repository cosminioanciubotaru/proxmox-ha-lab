# Proxmox HA Lab on GCP: Lab Log

## Status
- Current phase: 4 (Ceph) - not started
- Trial activated: 2026-09-13
- Trial ends: 2026-12-13 (90 days) or when credit is exhausted
- Credit remaining: EUR 256 of EUR 257 (as of 2026-09-14)
- VMs running: none (all stopped)

## Environment
- Admin workstation: Windows + WSL2 (Debian 13.5)
- Toolchain: git 2.47.3, gcloud CLI 584.0.0
- GCP project ID: proxmox-ha-lab-2026 (billing account ID intentionally not published)
- Region/zone: europe-west3-c (Frankfurt)
- VPC: pve-net, subnet pve-subnet 10.10.0.0/24, MTU 1460
- Internal IPs: pve1 10.10.0.2, pve2 10.10.0.3, pve3 10.10.0.4, pbs 10.10.0.6
- Proxmox VE 9.2.20, kernel 7.0.14-17-pve on all three nodes
- Cluster: pve-cluster, 3 nodes, quorate, quorum 2 of 3

## Disk layout (device letters are NOT consistent)
- pve1: boot=sda, ceph=sdb
- pve2: boot=sdb, ceph=sda
- pve3: boot=sda, ceph=sdb
- pbs:  50 GB pd-standard data disk

## Done
- Phase 0: GitHub repo, WSL2 Debian workstation, git + SSH key, gcloud CLI
- Phase 1: trial activated, budget alerts 25/50/75/90, project, VPC, firewall, Cloud NAT, 4 VMs, nested virt (VT-x) verified
- Phase 2: Proxmox VE installed on all three nodes from Debian 13 + no-subscription repo
- Phase 3: three-node cluster created and quorate

## Next
- Phase 4 Ceph:
  1. lsblk on each node to confirm the empty 50 GB disk (pve2 differs!)
  2. pveceph install on all three
  3. pveceph init, monitor on each node
  4. one OSD per node from the 50 GB disks
  5. create pool, add as Proxmox storage
  6. verify ceph -s shows HEALTH_OK
- Watch for memory pressure: 8 GB per node is tight for Ceph

## Decisions
- Google Cloud over Azure: Azure trial capped at 4 vCPUs and 30 days
- Sizing 8 vCPUs total: GCP Free Trial allows max 8 concurrent cores
- Nested virtualization on cloud: no local hardware available
- WSL2 Debian workstation: bash commands run unchanged on nodes, no CRLF issues
- europe-west3 over cheaper US regions: ~20ms vs ~110ms; Corosync is latency-sensitive
- All 4 VMs in one zone: cross-zone traffic is billed and adds latency; this lab demonstrates Proxmox HA, not cloud HA
- Custom VPC instead of the default network: default has 42 subnets and permits SSH from 0.0.0.0/0
- Budget "Alerts only" not "Spend cap enforcement": cap is Preview and pauses usage, which would corrupt HA/Ceph tests
- Cloud NAT over public IPs: cost is comparable, but no public IP means no address to scan
- pve nodes pd-balanced (SSD, Ceph is latency-sensitive); pbs pd-standard (sequential backup throughput)
- Proxmox installed on Debian rather than the ISO: no Proxmox image on GCP, and it shows PVE is a package layer on Debian
- Administration via cosmin@pam with the Administrator role, not root@pam
- Guest networking will use SDN/VXLAN: GCP does not forward frames with unknown MAC addresses

## Problems and fixes
- LAB_LOG.md mangled by clipboard paste; fixed by writing with a shell heredoc
- SSD_TOTAL_GB quota (250 GB) blocked PBS: 3 nodes on pd-balanced used 210 GB. Fixed with pd-standard for PBS
- IAP tunnel to 8006 failed with "4003: failed to connect to backend": firewall only allowed tcp:22 from the IAP range. Added pve-allow-iap-webui for 8006/8007 from 35.235.240.0/20
- Web login failed 401 despite correct password: a Linux user is not automatically a Proxmox user. Fixed with pveum user add cosmin@pam plus the Administrator role
- GRUB install failed on pve2: disk letters are swapped there (boot=sdb). Kernel assigns sdX in detection order, which is not guaranteed
- apt update broke with 401 Unauthorized: proxmox-ve adds the enterprise repo. Disabled with "Enabled: no" in pve-enterprise.sources on all three nodes

## Critical reminders
- PHASE 4: run "lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS" per node before touching any disk. Never assume sdb
- PHASE 5: GCP VPC MTU is 1460; VXLAN adds 50 bytes, so guest MTU must be 1410. Wrong MTU = small packets work, large transfers hang
- Web UI requires an IAP tunnel: ./scripts/tunnel.sh pve1
- Stop all VMs at session end: gcloud compute instances stop pve1 pve2 pve3 pbs --zone=europe-west3-c

## Evidence captured
- 01/02-budget-alerts.png, 03-vpc-firewall.png, 04-vm-instances.png
- 05-grub-disk-selection.png, 06-serial-console.png
- 08-proxmox-ui-first-login.png, 10-cluster-three-nodes.png
- docs/01-quota, 02-network, 03-vms, 04-nested-virt-check, 05-proxmox-install, 06-cluster
- 2026-09-15: disk letters changed across reboot. pve2 was boot=sdb/ceph=sda yesterday, today all three are boot=sda/ceph=sdb. Confirms device letters are assigned per boot and must never be recorded as fixed. Always re-check with lsblk in the same session as any disk operation.
- pve2 boots in EFI mode but has grub-pc (BIOS) installed, not grub-efi-amd64. GRUB updates therefore do not reach the ESP that pve2 actually boots from. Not breaking anything now; to fix later with: apt install grub-efi-amd64
- Ceph version mismatch: pve1 installed 19.2.3 Squid, pve2 installed 20.2 Tentacle from the same ceph-tentacle repository. Must be evened up before initializing the Ceph cluster.
- evidence/11-ceph-health-ok.png (Ceph HEALTH_OK, 3 OSDs, 3 monitors in the UI)

## Plan revision 2026-09-16: two levels of failover
Phase 6 (hypervisor HA): restart-based failover of ct:100. Node dies, cluster
restarts the guest elsewhere. Downtime to be measured, expected 60-120s.
This is what all hypervisor HA does (Proxmox, VMware HA, Hyper-V): when a node
loses power its RAM is gone, so a fresh start elsewhere is the only option.

Phase 8 addition (application-level redundancy): two web server containers on
different nodes serving the same static site, fronted by a keepalived virtual
IP. Both run simultaneously, so a node failure means sub-second failover with
no restart. Depends on Phase 5 networking.

Both will be tested with measured downtime. The point of documenting both:
hypervisor HA covers everything including services that cannot be clustered;
application redundancy covers those that can, with far lower downtime.
Also to demonstrate: live migration of a running KVM VM (zero downtime for
PLANNED maintenance, unlike unplanned node loss).

## Session 2026-09-16
- Phase 6 HA: ct:100 added to HA management (max_restart 3, max_relocate 3), fencing armed
- Failover test 1 (instances reset pve2): NO failover - node rebooted faster than Corosync's detection threshold, all 3 nodes stayed in membership. Correct behaviour, not a fault
- Failover test 2 (instances stop pve2): ct:100 recovered on pve1 in ~30s, measured at 13s poll resolution
- One node loss triggered three independent failovers: the guest, the Ceph manager (standby promoted), and the HA CRM master role. None moved back on recovery
- Ceph returned to HEALTH_OK immediately when pve2 came back
- Created KVM VM 101 (test-vm, 512 MB, 4 GB disk on vm-storage) for the live migration test
- Live migration BLOCKED: the Alpine ISO was attached from pve1's local storage, which pve3 cannot read. Proxmox refused rather than silently copying it. Demonstrates the shared-storage requirement precisely
- Next: detach ide2, retry qm migrate 101 pve3 --online

## Next session
1. qm set 101 --delete ide2, then qm migrate 101 pve3 --online (zero-downtime live migration of a running VM)
2. Then Phase 5: SDN/VXLAN guest networking. Remember MTU 1410 (GCP VPC is 1460, VXLAN adds 50 bytes)

## Session 2026-09-22
- Credit EUR 247 of 257, 82 days left
- Live migration of VM 101 pve1 -> pve3: 30 ms downtime, 138 MiB RAM transferred, 7 s total
- Proven from inside the guest: login session survived, uptime continuous (19 -> 35 min), per-second tick file has no gap
- Correction: CD must be EJECTED from the running VM (ide2 none), not deleted before boot; deleting first left the VM with nothing to boot
- Phase 6 complete: HA failover (unplanned, ~30 s) and live migration (planned, 30 ms) both measured
- evidence/14-live-migration-proof.png
- Phase 5 (partial): VXLAN zone gvxlan / VNet gnet live on all 3 nodes, guest net 10.20.0.0/24, MTU 1410
- Cross-node guest ping pve3 -> pve1 works; MTU boundary verified at exactly 1410
- Finding: SDN apply reloads network on all nodes regardless of zone node list
- Decision: VXLAN over GCP custom routes (routes are static, guests move)
- evidence/15-vxlan-cross-node-ping.png
- Next: internet access for guests
- Guest internet access working (stage 1): manual gateway 10.20.0.1 on pve1's gnet, ip_forward, MASQUERADE to ens4. ct:100 reached 1.1.1.1 and completed apt-get update (16.9 MB)
- Finding: VXLAN zones ignore subnet Gateway/SNAT (layer 3 zones only), so the gateway is built by hand
- Observed: guest throughput only 174 kB/s, DNS returns IPv6-only for deb.debian.org while the guest net is IPv4-only
- Config is temporary and lost on reboot; stage 2 is keepalived across all 3 nodes
- Phase 5 COMPLETE. Gateway 10.20.0.1 is now a keepalived/VRRP virtual IP across all three nodes
- Each node also has a permanent address on gnet (.11/.12/.13): VRRP needs a real source address on the interface, otherwise keepalived stays in FAULT
- ip_forward and the MASQUERADE rule made persistent (sysctl.d file + guest-nat.service)
- Gateway failover test: pve1 powered off, address moved to pve2, container lost 0 packets
- Reboot test on pve1: everything returned, and nopreempt correctly kept the gateway on pve2
- evidence/16-vrrp-gateway-failover.png, evidence/17-gateway-failover-no-packet-loss.png
