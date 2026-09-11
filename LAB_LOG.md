# Proxmox HA Lab on GCP: Lab Log

## Status
- Current phase: 0 (Prep)
- Trial activated: not yet (clock starts at billing account creation)
- Trial ends: earlier of activation + 3 months or $300 spent
- Credit remaining: $300 (not activated)
- VMs running: none

## Environment
- Admin workstation: Windows + WSL2 (Debian), in progress
- GCP project ID: (redacted in public repo)
- Region/zone: -
- Internal IPs: pve1 -, pve2 -, pve3 -, pbs -

## Done
- GitHub repo created (public, MIT license)

## Next
- Install WSL2 Debian; install git and gcloud CLI inside WSL
- Clone repo, create folder structure and .gitignore
- Read Proxmox docs: Cluster Manager, Ceph, HA, SDN

## Decisions
- Google Cloud over Azure: Azure trial capped at 4 vCPUs and 30 days (add source)
- Sizing = 8 vCPUs total: GCP Free Trial allows max 8 concurrent cores (https://cloud.google.com/terms/trial, section 3.1)
- Nested virtualization on cloud: no local hardware available
- Admin workstation on WSL2 Debian: bash commands in docs run unchanged on nodes, OpenSSH instead of bundled PuTTY, no CRLF line-ending issues

## Problems and fixes
- (none yet)

## Evidence captured
- (none yet)
