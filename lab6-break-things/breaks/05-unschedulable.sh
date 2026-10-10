#!/usr/bin/env bash
# SYMPTOM: Pending, forever. Nothing is crashing. Nothing is restarting.
#
# Note it sets the LIMIT as well as the request. The first version of this
# script only raised the request, and the API server rejected the whole patch:
#
#   The Deployment "api" is invalid: spec.template.spec.containers[0]
#   .resources.requests: Invalid value: "64Gi": must be less than or equal
#   to memory limit of 256Mi
#
# A request may never exceed its own limit — that is validated at admission,
# before the scheduler ever sees the pod. Worth knowing: it is the difference
# between "my manifest was rejected" and "my pod won't schedule", which are
# two completely different problems with two completely different fixes.
set -euo pipefail
kubectl -n lab3 patch deploy api --type=strategic -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"api","resources":{"requests":{"memory":"64Gi","cpu":"32"},"limits":{"memory":"64Gi"}}}]}}}}'
echo
echo "  No node has 64Gi. Where does Kubernetes tell you that?"
