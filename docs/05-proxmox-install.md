# Phase 2: Proxmox VE on Debian 13 (pve1)

## Why install on Debian instead of the Proxmox ISO
- No Proxmox image exists on GCP, and Marketplace images are excluded by the zero-cost rule
- Installing on Debian is a documented, supported path and makes clear that PVE is a package layer on Debian, not a monolithic appliance

## Steps
1. Confirmed hostname (pve1) and that it resolves to the internal IP 10.10.0.2
   - Google's image already provides a correct /etc/hosts entry; a manually added duplicate was removed
2. Added the Proxmox no-subscription repository with its signing key (enterprise repo needs a paid subscription)
3. apt full-upgrade, then installed proxmox-default-kernel
   - GRUB installed to /dev/sda only, never to /dev/sdb (the Ceph disk)
   - Kept the local /etc/default/grub: it holds Google's serial console settings
4. Verified serial console access BEFORE rebooting, and set a password so the console is usable for login
5. Rebooted; confirmed running kernel 7.0.14-16-pve. Debian's kernel remains in the GRUB menu as a fallback
6. Installed proxmox-ve, postfix (Local only), open-iscsi, chrony
   - chrony matters: Corosync and Ceph both fail confusingly when node clocks drift
7. Registered cosmin@pam as a Proxmox user with the Administrator role
   - A Linux account alone is not enough; Proxmox keeps its own user database
   - Day-to-day administration via a named account rather than root@pam

## Web UI access
- pveproxy listens on 8006; no public IP on any node
- Access via: gcloud compute start-iap-tunnel pve1 8006 --local-host-port=localhost:8006 --zone=europe-west3-c
- Browser: https://localhost:8006 (self-signed certificate warning is expected)

## Correction made during this phase
- The initial firewall allowed only tcp:22 from the IAP range, so the 8006 tunnel failed with "4003: failed to connect to backend"
- Added pve-allow-iap-webui for tcp:8006 and tcp:8007 from 35.235.240.0/20
- This is not public exposure: the source is Google's authenticated IAP proxy, and traffic only flows after Google verifies the user's identity

## Enterprise repository (post-install issue)
- Installing proxmox-ve adds /etc/apt/sources.list.d/pve-enterprise.sources, which requires a paid subscription
- Without one it returns 401 Unauthorized and apt update fails entirely, blocking all package operations
- Disabled by appending "Enabled: no" to the deb822-format file on all three nodes, rather than deleting it: the file remains as a record and can be re-enabled with a one-word change
- The no-subscription repository remains the only Proxmox source, per the zero-cost constraint
- All three nodes then brought to the same version: kernel 7.0.14-17-pve, pve-manager 9.2.20
