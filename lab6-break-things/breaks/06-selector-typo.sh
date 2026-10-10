#!/usr/bin/env bash
# SYMPTOM: connection refused, but every pod is Running and Ready.
# The silent one. No event, no log, no failing probe.
#
# Patches BOTH Services. The first version only broke `svc/api`, and the
# lab's own curl still worked -- because localhost:8080 reaches the cluster
# through `svc/api-nodeport`, which has its own copy of the selector.
#
# That is itself the lesson in miniature: a selector is duplicated into every
# Service that fronts the same pods, and fixing one does not fix the others.
set -euo pipefail
kubectl -n lab3 patch svc api          --type=merge -p '{"spec":{"selector":{"app":"api-v2"}}}'
kubectl -n lab3 patch svc api-nodeport --type=merge -p '{"spec":{"selector":{"app":"api-v2"}}}'
echo
echo "  Every pod is Running and Ready. Nothing logs an error. Now try to reach it."
