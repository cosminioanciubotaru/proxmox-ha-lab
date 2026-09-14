# Proxmox HA Lab on GCP: Lab Log

## Status
- Current phase: 1 (GCP setup) - VMs created, verifying nested virtualization
- Trial activated: 2026-09-13
- Trial ends: 2026-12-13 (90 days) or when credit is exhausted
- Credit remaining: EUR 257.47 of EUR 257.47 (as of 2026-09-13)
- VMs running: pve1, pve2, pve3, pbs (all 4, billing active)

## Environment
- Admin workstation: Windows + WSL2 (Debian 13.5)
- Toolchain: git 2.47.3, gcloud CLI 584.0.0
- GCP project ID: proxmox-ha-lab-2026 (billing account ID intentionally not published)
- Organization: auto-created at signup
- Region/zone: europe-west3 (Frankfurt)
- Internal IPs: pve1 10.10.0.2, pve2 10.10.0.3, pve3 10.10.0.4, pbs 10.10.0.6

## Done
- GitHub repo created (public, MIT license)
- WSL2 Debian workstation set up; git identity, SSH key, repo cloned
- .gitignore for secrets, repo folder structure (docs/ configs/ scripts/ evidence/)
- gcloud CLI installed via Google signed apt repository
- Free Trial activated 2026-09-13, EUR 257.47 credit
- Budget alerts 25/50/75/90 percent (Actual), alerts-only, billing-account scope

## Next
- Create dedicated GCP project, enable Compute Engine API
- gcloud auth login, set default project/region/zone
- Check vCPU quota in europe-west3
- Create VPC and firewall rules
- Create 4 VMs with nested virtualization

## Decisions
- Google Cloud over Azure: Azure trial capped at 4 vCPUs and 30 days (add source)
- Sizing = 8 vCPUs total: GCP Free Trial allows max 8 concurrent cores (https://cloud.google.com/terms/trial, section 3.1)
- Nested virtualization on cloud: no local hardware available
- Admin workstation on WSL2 Debian: bash commands in docs run unchanged on nodes, OpenSSH instead of bundled PuTTY, no CRLF line-ending issues
- Region europe-west3 (Frankfurt) over cheaper US regions: ~20ms vs ~110ms latency; Corosync is latency-sensitive and the web UI is used heavily
- Budget "Alerts only" instead of "Spend cap enforcement": cap is Preview, covers limited services only, and pauses usage - a pause mid-test would corrupt HA/Ceph experiments

## Problems and fixes
- LAB_LOG.md got mangled when pasted via Notepad (Markdown escaped, lines prefixed). Fixed by writing the file with a shell heredoc instead of the clipboard.

## Evidence captured
- evidence/01-budget-alerts.png (redacted)
- evidence/02-budget-alerts.png (redacted)
- Guest networking via Proxmox SDN/VXLAN, not plain Linux bridging: GCP's virtual network does not forward frames with unknown MAC addresses, so LXC/VM guests bridged onto vmbr0 are silently dropped. VXLAN encapsulates guest layer-2 traffic in UDP between the nodes' own IPs, which GCP accepts as normal node-to-node traffic.
- evidence/03-vpc-firewall.png (firewall rules in console, redacted)
- SSD_TOTAL_GB quota (250 GB/region) blocked PBS creation: 3 pve nodes with pd-balanced already used 210 GB. Fixed by giving PBS pd-standard disks, which count against DISKS_TOTAL_GB (2048 GB) instead. Justified: PBS is a sequential throughput workload; Ceph is latency-sensitive and keeps SSD.
- evidence/04-vm-instances.png (4 VMs running, External IP column empty)

## Session 2026-09-14
- Created VPC pve-net (10.10.0.0/24), firewall rules, Cloud NAT for outbound-only internet
- Created 4 VMs; hit SSD_TOTAL_GB quota, resolved by putting PBS on pd-standard
- Verified nested virtualization (VT-x) active on pve1
- Installed Proxmox VE 9.2.18 on pve1: repo, kernel 7.0.14-16-pve, reboot, proxmox-ve packages
- Verified serial console access before the kernel reboot; set console passwords
- Added firewall rule for 8006/8007 from the IAP range after the tunnel failed with 4003
- Registered cosmin@pam with the Administrator role; web UI reachable at https://localhost:8006 via IAP tunnel
- All VMs stopped at session end

## Next session
- pve2 and pve3: same Proxmox install (hostname, passwd, repo, kernel, reboot, proxmox-ve)
- Then create the cluster with pvecm on pve1, join pve2 and pve3
- Remember: GCP VPC MTU is 1460; guest MTU must be 1410 for VXLAN in Phase 5
- Disk device letters are NOT consistent across nodes: pve1 has boot=sda, ceph=sdb; pve2 has boot=sdb, ceph=sda. Kernel assigns sdX in detection order, which is not guaranteed. GRUB install failed on pve2 until the correct disk was selected.
- PHASE 4 RULE: before giving any disk to Ceph, run "lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS" on that node and identify the 50 GB disk with no mountpoint. Never assume sdb.
