#!/usr/bin/env bash
# SYMPTOM: writes start failing; the app's own logs blame something else.
#
# ⚠️ READ THIS — it is the actual lesson of this break.
#
# kind's default StorageClass is `standard`, backed by the local-path
# provisioner, which does NOT ENFORCE the requested size. `storage: 1Gi` in
# the volumeClaimTemplate is recorded, reported by `kubectl get pvc`, and then
# completely ignored: the volume is a bind-mounted directory on the node's
# filesystem and can grow until the NODE's disk is full.
#
# Prove it to yourself below: /data reports the node's whole disk (tens of GB),
# not 1Gi. So on kind you cannot fill a PVC -- you can only fill the node,
# which is break 09.
#
# This matters beyond the lab. "The PVC says 1Gi" tells you what was REQUESTED,
# never what is ENFORCED, and enforcement is entirely a property of the
# StorageClass and its provisioner:
#
#   Azure Disk / AWS EBS / GCE PD  -> a real block device. 1Gi means 1Gi.
#                                     ENOSPC at 1Gi, and the pod is NOT evicted
#                                     (the node has plenty of space) -- the app
#                                     just starts failing writes.
#   local-path (kind, k3s)         -> a directory. No limit. Fills the node.
#   hostPath                       -> a directory. No limit. Fills the node.
#   NFS / Azure Files              -> depends entirely on the share's quota.
#
# The failure modes are genuinely different, and so is the fix. On a real disk
# you expand the PVC (`allowVolumeExpansion: true`). On local-path you have a
# NODE problem wearing a volume costume.
set -euo pipefail

echo "  StorageClass and what it actually enforces:"
kubectl -n lab3 get pvc data-redis-0 -o custom-columns=\
'NAME:.metadata.name,REQUESTED:.spec.resources.requests.storage,SC:.spec.storageClassName' 2>/dev/null

echo
echo "  What the pod really sees at /data:"
kubectl -n lab3 exec redis-0 -- df -h /data | tail -1

echo
cat <<'TXT'
  ^ If that Size is far larger than the REQUESTED value, the quota is not
    enforced and this break cannot fill the volume. That is the finding.

  The command that WOULD have warned you on a real cluster, days early:

    kubelet_volume_stats_available_bytes / kubelet_volume_stats_capacity_bytes

  Alert on that ratio below ~15%. Nothing in Kubernetes warns you by default,
  and a full PVC produces no event, no restart, and no useful pod status --
  only application errors that look like something else entirely.

  To see a real ENOSPC, run this against a cluster whose StorageClass enforces
  size (AKS/EKS/GKE), or move on to break 09, which fills the node instead.
TXT
