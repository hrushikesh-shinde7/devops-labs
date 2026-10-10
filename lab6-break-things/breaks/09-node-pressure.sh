#!/usr/bin/env bash
# SYMPTOM: pods evicted from a node you weren't even looking at.
#
# ⚠️ THIS ONE WRITES A LARGE FILE TO YOUR DISK. Read before running.
#
# The kubelet evicts when `nodefs.available` drops below 10% (the default
# hard threshold). kind nodes share your Docker VM's filesystem, so to cross
# that line the script must fill your REAL disk to ~90%. On a typical setup
# that is tens of gigabytes.
#
# It therefore: refuses to run without --confirm, computes the exact size
# needed, refuses if that would leave the host uncomfortably tight, and always
# removes the file on exit (including on Ctrl-C).
set -euo pipefail

NODE=$(kubectl get nodes -o name | grep worker | head -1 | cut -d/ -f2)
FILLER=/filler

cleanup() {
  echo
  echo "cleaning up ${FILLER} on ${NODE}"
  docker exec "$NODE" rm -f "$FILLER" 2>/dev/null || true
  kubectl uncordon "$NODE" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

read -r SIZE_K AVAIL_K <<<"$(docker exec "$NODE" sh -c "df -k / | tail -1 | awk '{print \$2, \$4}'")"
AVAIL_G=$((AVAIL_K / 1024 / 1024))
# Target: leave 8% free, i.e. below the kubelet's 10% hard eviction threshold.
TARGET_FREE_K=$((SIZE_K * 8 / 100))
FILL_K=$((AVAIL_K - TARGET_FREE_K))
FILL_G=$((FILL_K / 1024 / 1024))

echo "node:            $NODE"
echo "disk total:      $((SIZE_K / 1024 / 1024)) GiB"
echo "currently free:  ${AVAIL_G} GiB"
echo "would write:     ${FILL_G} GiB  (to cross the 10% eviction threshold)"
echo

if [ "${1:-}" != "--confirm" ]; then
  cat <<TXT
NOT RUNNING. This would write ${FILL_G} GiB to the disk backing your Docker VM.

If ${FILL_G} GiB is more than you want to spend, skip this break -- you can see
the same eviction ORDER (BestEffort -> Burstable -> Guaranteed) in Lab 3
Exercise 6 without filling anything, and the diagnostic commands are the
valuable part regardless:

  kubectl describe node $NODE | grep -A8 Conditions
  kubectl get events -A --field-selector reason=Evicted

To proceed anyway:  ./breaks/09-node-pressure.sh --confirm
TXT
  trap - EXIT INT TERM     # nothing was created; don't run cleanup
  exit 0
fi

if [ "$FILL_G" -lt 1 ]; then
  echo "Disk is already near the threshold; nothing to do."
  trap - EXIT INT TERM
  exit 0
fi

echo "writing ${FILL_G} GiB... (Ctrl-C is safe -- the file is removed on exit)"
docker exec "$NODE" sh -c "fallocate -l ${FILL_K}K $FILLER 2>/dev/null \
  || dd if=/dev/zero of=$FILLER bs=1M count=$((FILL_K / 1024)) status=none"

echo
echo "watch the node go DiskPressure:"
for i in $(seq 1 12); do
  COND=$(kubectl get node "$NODE" -o jsonpath='{range .status.conditions[?(@.type=="DiskPressure")]}{.status}{end}')
  echo "  t=$((i*10))s  DiskPressure=$COND"
  [ "$COND" = "True" ] && break
  sleep 10
done

echo
echo "evicted pods:"
kubectl get events -A --field-selector reason=Evicted 2>/dev/null | tail -5

echo
echo "press Enter to clean up"
read -r _
