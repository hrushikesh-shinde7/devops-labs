#!/usr/bin/env bash
# SYMPTOM: ImagePullBackOff / ErrImagePull
set -euo pipefail
kubectl -n lab3 set image deploy/api api=lab3-api:v99-does-not-exist
cat <<'TXT'

  Diagnose it yourself before reading the answer file.
  Your first three commands?

TXT
