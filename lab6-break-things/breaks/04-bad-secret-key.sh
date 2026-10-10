#!/usr/bin/env bash
# SYMPTOM: CreateContainerConfigError — and note the pod never even STARTS,
# so there are no application logs to read. That is the tell.
set -euo pipefail
kubectl -n lab3 patch deploy api --type=strategic -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"api","env":[{"name":"DB_PASSWORD","valueFrom":{"secretKeyRef":{"name":"app-secret","key":"NO_SUCH_KEY"}}}]}]}}}}'
