#!/usr/bin/env bash
# SYMPTOM: everything is broken. Genuinely everything.
#
# This is the outage that teaches humility: the blast radius of one small
# component. Scale, don't delete — the Deployment would just recreate it.
set -euo pipefail
kubectl -n kube-system scale deploy coredns --replicas=0
echo
echo "  Now: kubectl -n lab3 exec deploy/api -- python -c \"import socket;socket.gethostbyname('redis')\""
echo "  Every service-to-service call in the cluster now fails by NAME, not by network."
