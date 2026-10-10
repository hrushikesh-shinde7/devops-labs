#!/usr/bin/env bash
# NOT a break — the opposite. A PDB REFUSING a drain is the safety net working.
# People file this as a bug. It is the feature.
set -euo pipefail
kubectl -n lab3 scale deploy api --replicas=1
NODE=$(kubectl -n lab3 get pod -l app=api -o jsonpath='{.items[0].spec.nodeName}')
echo "draining $NODE — the PDB (minAvailable: 1) should refuse"
kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data --timeout=60s || true
echo
echo "  Read the error. Then: kubectl uncordon $NODE"
