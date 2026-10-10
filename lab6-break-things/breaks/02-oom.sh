#!/usr/bin/env bash
# SYMPTOM: pod restarts, exit code 137
set -euo pipefail
kubectl -n lab3 patch deploy api --type=strategic -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"api","resources":{"limits":{"memory":"96Mi"},"requests":{"memory":"64Mi","cpu":"100m"}}}]}}}}'
echo
echo "  Now drive it: curl 'localhost:8080/burn?mb=300'"
