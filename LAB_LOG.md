# \# Proxmox HA Lab on GCP: Lab Log

# 

# \## Status

# \- Current phase: 1 (GCP setup)

# \- Trial activated: 2026-09-13

# \- Trial ends: 2026-12-13 (90 days) or when credit is exhausted

# \- Credit remaining: EUR 257.47 of EUR 257.47 (as of 2026-09-13)

# \- VMs running: none

# 

# \## Environment

# \- Admin workstation: Windows + WSL2 (Debian 13.5)

# \- Toolchain: git 2.47.3, gcloud CLI 584.0.0

# \- GCP project ID: (redacted in public repo)

# \- Organization: auto-created at signup

# \- Region/zone: europe-west3 (Frankfurt)

# \- Internal IPs: pve1 -, pve2 -, pve3 -, pbs -

# 

# \## Done

# \- GitHub repo created (public, MIT license)

# \- WSL2 Debian workstation set up; git identity, SSH key, repo cloned

# \- .gitignore for secrets, repo folder structure (docs/ configs/ scripts/ evidence/)

# \- gcloud CLI installed via Google signed apt repository

# \- Free Trial activated 2026-09-13, EUR 257.47 credit

# \- Budget alerts 25/50/75/90 percent (Actual), alerts-only, billing-account scope

# 

# \## Next

# \- Create dedicated GCP project, enable Compute Engine API

# \- gcloud auth login, set default project/region/zone

# \- Check vCPU quota in europe-west3

# \- Create VPC and firewall rules

# \- Create 4 VMs with nested virtualization

# 

# \## Decisions

# \- Google Cloud over Azure: Azure trial capped at 4 vCPUs and 30 days (add source)

# \- Sizing = 8 vCPUs total: GCP Free Trial allows max 8 concurrent cores (https://cloud.google.com/terms/trial, section 3.1)

# \- Nested virtualization on cloud: no local hardware available

# \- Admin workstation on WSL2 Debian: bash commands in docs run unchanged on nodes, OpenSSH instead of bundled PuTTY, no CRLF line-ending issues

# \- Region europe-west3 (Frankfurt) over cheaper US regions: \~20ms vs \~110ms latency; Corosync is latency-sensitive and the web UI is used heavily

# \- Budget "Alerts only" instead of "Spend cap enforcement": cap is Preview, covers limited services only, and pauses usage - a pause mid-test would corrupt HA/Ceph experiments

# 

# \## Problems and fixes

# \- (none yet)

# 

# \## Evidence captured

# \- evidence/01-budget-alerts.png (redacted)

# \- evidence/02-budget-alerts.png (redacted)

