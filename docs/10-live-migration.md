# Live migration test (2026-09-22)

## Goal
Prove a running KVM VM can move between nodes with no interruption.
This is the tool for PLANNED maintenance: empty a node, patch and reboot it,
move guests back. Contrast with HA failover (unplanned node loss), which is
restart-based and cost ~30 s of downtime in the Phase 6 test.

## Test subject
VM 101 (test-vm): 512 MB, 1 vCPU, 4 GB disk on Ceph pool vm-storage.
Booted Alpine Linux 3.21 from CD into RAM, then the CD was ejected
(qm set 101 --ide2 none,media=cdrom). The first attempt had been refused
because the ISO lived on pve1's local disk, which pve3 cannot read.

## Before
- Logged in as root on the serial console (qm terminal 101)
- uptime at 09:00:13: up 19 min
- Background loop writing the time once per second to /tmp/tick

## Migration
Command: qm migrate 101 pve3 --online
  migration downtime limit: 100 ms
  average migration speed: 512.5 MiB/s - downtime 30 ms
  migration completed, transferred 138.0 MiB VM-state
  migration finished successfully (duration 00:00:07)

Only RAM travelled (138 MiB). The 4 GB disk stayed in Ceph; pve3 already had access.

## After, checked from inside the VM on pve3
- Console showed localhost:~# immediately: the root session survived, no re-login
- uptime at 09:15:54: up 35 min (continuous from 19 min, never reset)
- /tmp/tick contains every second from 09:01:08 to 09:01:19, no gap,
  including the handover at 09:01:12-13

## Result
30 ms of pause, below the resolution of a once-per-second loop.
The VM did not restart and did not notice the move.

## Container vs VM
LXC (ct:100): pct migrate --restart, 5 s downtime, restarts
KVM (vm:101): qm migrate --online, 30 ms pause, keeps running
