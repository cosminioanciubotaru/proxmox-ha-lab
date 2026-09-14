#!/bin/bash
# Open an IAP tunnel to a node's web UI. Usage: ./tunnel.sh pve1 [local_port]
NODE="${1:-pve1}"
PORT="${2:-8006}"
echo "Tunnel: https://localhost:$PORT -> $NODE:8006  (Ctrl+C to close)"
gcloud compute start-iap-tunnel "$NODE" 8006 --local-host-port="localhost:$PORT" --zone=europe-west3-c
