# Phase 6: HA Failover Tests

## Setup
- ct:100 (test-ct) added to HA: ha-manager add ct:100 --state started --max_restart 3 --max_relocate 3
- max_restart 3: try restarting on the same node 3 times before giving up on it
- max_relocate 3: then try relocating to another node up to 3 times
- Without these limits a guest that crashes on start would loop forever between nodes
- ha-manager status showed "fencing armed (CRM watchdog active)": a node that loses
  quorum reboots itself via watchdog, so it cannot keep writing to shared storage
  while the cluster restarts its guests elsewhere

## Test 1: hard reset (gcloud compute instances reset pve2)
Result: NO failover occurred.
pve2 rebooted and rejoined before Corosync declared it dead. pvecm showed all three
nodes still in membership throughout.

This is correct behaviour, not a fault. Corosync tolerates short interruptions
deliberately: failing over on every transient blip would cause more disruption than
it prevents. A node must be unreachable past the detection threshold before the
cluster acts.

## Test 2: power off (gcloud compute instances stop pve2)
Result: failover to pve1 succeeded.

Timeline from a 10-second polling loop against ha-manager status:
  10:57:52  service ct:100 (pve2, started)   <- last healthy poll
  10:58:05  service ct:100 (pve1, starting)  <- already relocated
  10:58:18  service ct:100 (pve1, started)   <- running on the new node

Recovery within approximately 30 seconds. Measurement resolution is the 13-second
poll interval, so the true detection point lies inside that window.

No manual intervention. The cluster detected the node loss, fenced it, and restarted
the container on a surviving node.

## Why this works
- Corosync reports the node gone
- Quorum (2 of 3) confirms the survivors may act
- Ceph means pve1 can already read the container's disk; nothing is copied
- The HA manager decides where to restart and does so
Remove any one of these and there is no failover.

## Honest limitation
This is restart-based failover, not zero downtime. When a node loses power its RAM
is gone, so a fresh start elsewhere is the only option. All hypervisor-level HA works
this way (Proxmox, VMware HA, Hyper-V failover clustering).

Zero downtime for PLANNED maintenance is a different case and is achievable: live
migration moves a running KVM VM between nodes with no interruption.

Zero downtime for UNPLANNED node loss requires redundancy at the application layer:
two instances running simultaneously behind a virtual IP. Tested separately in Phase 8.

## Recovery after pve2 returned
- Ceph: HEALTH_OK immediately, 3 OSDs up. The pool holds almost no data, so
  re-replication of the missing third copy was instant.
- ct:100 stayed on pve1. HA does not move guests back when a node returns:
  another relocation would mean another interruption for no benefit.

## Three independent failovers from one node loss
Killing pve2 triggered failover at three separate layers, all automatic:
  1. ct:100          pve2 -> pve1   (HA manager restarted the guest)
  2. Ceph manager    pve2 -> pve1   (standby MGR took over)
  3. HA CRM master   pve2 -> pve3   (another node took the master role)
None of these required intervention, and none of them moved back afterwards.
This is why a second MGR was created in Phase 4 rather than leaving a single one:
without a standby, losing that node would have left the cluster without its
management and metrics layer during the incident.
