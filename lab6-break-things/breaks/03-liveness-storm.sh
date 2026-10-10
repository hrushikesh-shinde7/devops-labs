#!/usr/bin/env bash
# SYMPTOM: healthy app, endless restarts
set -euo pipefail
kubectl -n lab3 set env deploy/api SLOW_MODE=true
kubectl -n lab3 patch deploy api --type=strategic -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"api","livenessProbe":{"httpGet":{"path":"/healthz/live","port":"http"},"periodSeconds":5,"timeoutSeconds":1,"failureThreshold":1}}]}}}}'
