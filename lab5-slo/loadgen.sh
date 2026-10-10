#!/usr/bin/env bash
# Steady traffic so the SLO windows have data. Without a baseline rate, a
# handful of errors looks like a 100% error rate — a real and common way to
# fool yourself with ratio metrics on low-traffic services.
set -euo pipefail
URL="${1:-http://localhost:8000/api/orders}"
RPS="${2:-10}"
INTERVAL=$(python3 -c "print(1/$RPS)")

echo "driving $RPS req/s at $URL — Ctrl-C to stop"
trap 'echo; echo "stopped"; exit 0' INT

while true; do
  curl -s -o /dev/null -w '' "$URL" &
  sleep "$INTERVAL"
done
