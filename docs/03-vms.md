# VM Inventory

| Name | Machine type | vCPU/RAM | Boot disk | Extra disk | Internal IP | Nested virt | Tag |
|------|--------------|----------|-----------|------------|-------------|-------------|-----|
| pve1 | n2-standard-2 | 2 / 8 GB | 20 GB pd-balanced | 50 GB pd-balanced (Ceph) | 10.10.0.2 | yes | pve-node |
| pve2 | n2-standard-2 | 2 / 8 GB | 20 GB pd-balanced | 50 GB pd-balanced (Ceph) | 10.10.0.3 | yes | pve-node |
| pve3 | n2-standard-2 | 2 / 8 GB | 20 GB pd-balanced | 50 GB pd-balanced (Ceph) | 10.10.0.4 | yes | pve-node |
| pbs  | e2-medium     | 2 / 4 GB | 20 GB pd-standard | 50 GB pd-standard (datastore) | 10.10.0.6 | no | pbs-node |

Total: 8 vCPUs, exactly the Free Trial concurrent-core cap. No headroom for a fifth VM.
All VMs: no external IP, serial console enabled, zone europe-west3-c, subnet pve-subnet.

## Disk type decision
- pve nodes use pd-balanced (SSD-backed): Ceph is latency-sensitive with constant small I/O
- pbs uses pd-standard (HDD-backed): backups are sequential throughput, latency does not matter
- This also resolved the SSD_TOTAL_GB quota block (see below)

## Quota constraint hit
- pd-balanced counts against SSD_TOTAL_GB (limit 250 GB/region), NOT DISKS_TOTAL_GB (2048 GB)
- 3 pve nodes consumed 210 GB of the SSD quota; PBS needed 70 GB more and was rejected
- Lesson: check the quota matching the specific disk type, not just total disk quota

## Note
- pbs received 10.10.0.6, not .5: the failed creation attempt briefly held .5
