# Lab 6 — Break things on purpose

**Cost: £0.** Runs on the Lab 3 kind cluster.
**Time: half a day — and repeat it.** This is the one lab worth doing more than once.
**Prerequisite:** `make cluster deploy` in `../lab3-compose-to-k8s`.
**Companion doc:** `../../docx/12_Hands_On_Labs.docx` (Lab 6), `../../docx/03_Kubernetes.docx`.

---

## Why this is the highest-value hour in the pack

Every other lab builds. This one breaks.

**Interviewers love debugging questions** because they're the hardest to fake. "A pod is
stuck in Pending — what do you check?" cannot be answered from a blog post. It's answered
from memory or it's answered badly, and the difference is *audible* — the pause before
reasoning from first principles versus the immediate "I'd look at the scheduler's event
message."

What this lab gives you isn't a claim. It's an **instinct**.

---

## How to run it

**Do not read the answers first.** The value is entirely in the diagnosis attempt.

```bash
make random          # picks one of the ten, doesn't tell you which
make triage          # the three commands that start every diagnosis
```

For each break: **cause it → observe it → diagnose it with commands → fix it → write
down the path you took** in `RUNBOOK.md`.

```bash
make reset           # undo everything, back to a clean cluster
```

`make reset` **deletes** the Deployments rather than re-applying over them, and that's
deliberate. A failed rollout can **deadlock**: with `maxUnavailable: 0` the controller may
not scale the broken ReplicaSet down (availability would drop below desired), and with
`maxSurge: 1` it may not scale the good one up (it would breach the pod ceiling). Nothing
moves, and **`kubectl apply` of the correct spec does not rescue it** — the spec is
already correct; the rollout is stuck. In production you break it with `kubectl rollout
undo`, or by deleting the failed ReplicaSet. Recognising that deadlock is worth more than
any single break in this list.

---

## The ten

| # | Command | Symptom you'll see |
|---|---|---|
| 1 | `make b1` | `ImagePullBackOff` |
| 2 | `make b2` | Restarts, exit code 137 |
| 3 | `make b3` | Restart storm, app is fine |
| 4 | `make b4` | `CreateContainerConfigError` |
| 5 | `make b5` | `Pending`, forever |
| 6 | `make b6` | Connection refused, all pods Ready |
| 7 | `make b7` | Redis misbehaving, logs unhelpful |
| 8 | `make b8` | **Everything** is broken |
| 9 | `make b9` | Evictions on a node you weren't watching |
| 10 | `make b10` | A drain that refuses to proceed |

---

## The triage order — internalise this

```bash
kubectl -n lab3 get pods -o wide          # 1. what STATE is it in?
kubectl -n lab3 get events --sort-by=.lastTimestamp   # 2. what did the cluster TRY?
kubectl -n lab3 describe pod <name>       # 3. WHY is this one unhappy?
```

**Events before logs.** This is the single habit that separates people who debug
Kubernetes from people who debug applications. At least half the breaks below never
produce one line of application log — the container never started, or the failure is in
the platform, not the process. `kubectl logs` is your *fourth* command, not your first.

`make triage` runs all three in order.

---

## Answers — read only after you've tried

<details>
<summary><b>1 — ImagePullBackOff</b></summary>

`describe pod` → Events → `Failed to pull image ... not found`.

`ImagePullBackOff` is the *backoff state*; `ErrImagePull` is the underlying error, and
the kubelet backs off exponentially. Causes, in the order worth checking: wrong tag,
wrong registry path, missing `imagePullSecrets`, rate limiting.

**The distinguishing question:** private registry or public? A 401/403 in the event
message means auth; `not found` means the tag. Two completely different fixes.

**And the good news buried in it:** the old ReplicaSet is still serving. A bad image
with `maxUnavailable: 0` never takes traffic.
</details>

<details>
<summary><b>2 — OOMKilled</b></summary>

```bash
make why        # lastState.terminated.reason = OOMKilled, exitCode 137
```

137 = 128 + 9 = **SIGKILL**. The kernel's cgroup limit killed it. There is no signal your
app can catch, no graceful shutdown, no flush, no final log line. `kubectl logs
--previous` shows the output up to the instant it died and nothing about why.

**The trap:** people raise the limit. Sometimes right, often wrong — a slow leak just
takes longer to hit a higher ceiling. Check whether usage is *stable-but-high* (limit is
genuinely too low) or *climbing* (you have a leak, and the limit is the only thing
containing it).
</details>

<details>
<summary><b>3 — Liveness restart storm</b></summary>

Pods restart on a near-fixed interval, the app logs look completely normal, and requests
between restarts succeed.

`describe` → `Liveness probe failed: context deadline exceeded`.

**The app never broke. `timeoutSeconds: 1` against a 10-second handler is the entire
outage.** Worse: this fails *simultaneously across every replica*, because they all share
the cause. A probe misconfiguration is one of the few things that can take down a whole
fleet at once.

**Say it out loud: "the probe was the bug."** That sentence is the lesson.
</details>

<details>
<summary><b>4 — CreateContainerConfigError</b></summary>

`describe` → `couldn't find key NO_SUCH_KEY in Secret lab3/app-secret`.

**The tell is the absence of logs.** The container never started, so there is nothing to
`kubectl logs`. Any `*ConfigError` means the kubelet couldn't assemble the container
spec — missing Secret, missing ConfigMap, missing key, unresolvable volume.

Distinguish from `CrashLoopBackOff`, where the container *did* start and then died — that
one has logs, and `--previous` is where they are.
</details>

<details>
<summary><b>5 — Pending</b></summary>

```bash
kubectl -n lab3 describe pod <name> | grep -A5 Events
# 0/3 nodes are available: 3 Insufficient memory
```

**The scheduler writes you a precise sentence and most people never read it.** It tells
you exactly how many nodes it considered and why each was rejected.

Scheduling is decided on **requests**, not limits, and not actual usage. A node with 8 GB
free will still refuse a 64 GB request. Other flavours of the same message: `Insufficient
cpu`, `node(s) had untolerated taint`, `didn't match Pod's node affinity`, `had volume
node affinity conflict` (a RWO volume in a different AZ).

Note what is *not* happening: nothing crashes, nothing restarts, no logs are produced.
Pending is quiet.

**A related trap, which this break hit while it was being written:** a request may never
exceed its own limit. Ask for 64Gi while the limit is 256Mi and the API server rejects
the whole manifest at admission —

```
The Deployment "api" is invalid: spec.template.spec.containers[0].resources.requests:
Invalid value: "64Gi": must be less than or equal to memory limit of 256Mi
```

— so the pod is never created and the scheduler never sees it. *"My manifest was rejected"*
and *"my pod won't schedule"* look similar in a CI log and are completely different
problems. `breaks/05-unschedulable.sh` raises both together for that reason.
</details>

<details>
<summary><b>6 — Service with no endpoints</b></summary>

```bash
make endpoints        # ADDRESSES is empty
```

All pods Running, all Ready, zero restarts, no events, no failing probe. **Nothing in the
cluster reports an error.** The Service selector simply matches nothing.

**Make `get endpointslice` your reflex for "healthy pods, failing traffic."** The other
common cause of an empty EndpointSlice is every pod failing its *readiness* probe — same
symptom, different root cause, and the pod list distinguishes them instantly (`0/1 READY`
vs `1/1 READY`).

Also worth knowing: a Service selector matches **pod labels**, not the Deployment's
labels. They're usually the same, which is why people assume they must be.
</details>

<details>
<summary><b>7 — Full PVC (and why it won't fill on kind)</b></summary>

```bash
kubectl -n lab3 exec redis-0 -- df -h /data
```

**On kind, `/data` reports the node's entire disk — tens of GB — not the 1Gi the
volumeClaimTemplate asked for.** kind's default StorageClass is local-path, which records
the requested size and then ignores it: the volume is a bind-mounted directory that can
grow until the *node's* disk is full.

So this break cannot fill the volume here, and **that finding is the lesson**:

> `kubectl get pvc` tells you what was **requested**, never what is **enforced**.
> Enforcement is a property of the StorageClass and its provisioner.

| Provisioner | 1Gi means |
|---|---|
| Azure Disk / EBS / GCE PD | a real block device — ENOSPC at 1Gi, pod **not** evicted, app just starts failing writes |
| local-path (kind, k3s) | a directory — no limit, fills the node instead |
| hostPath | a directory — no limit |
| NFS / Azure Files | whatever the share's quota says |

The failure modes differ and so do the fixes: on a real disk you expand the PVC
(`allowVolumeExpansion: true`); on local-path you have a *node* problem wearing a volume
costume.

**The layer that's broken is not the layer that's complaining** — the general lesson of
the whole lab. A full PVC produces no event, no restart, and no useful pod status, only
application errors that look like something else. Nothing warns you by default; the metric
that would have, days earlier, is
`kubelet_volume_stats_available_bytes / kubelet_volume_stats_capacity_bytes`. *"We alert
on PVC utilisation"* is a good, specific thing to have an opinion about.
</details>

<details>
<summary><b>8 — CoreDNS gone</b></summary>

Every service-to-service call fails. Not connection-refused — **name resolution**.
Liveness probes using hostnames start failing, so pods begin restarting, which looks like
a cascading application failure and is not.

```bash
kubectl -n lab3 exec deploy/api -- python -c "import socket;socket.gethostbyname('redis')"
kubectl -n kube-system get pods -l k8s-app=kube-dns
```

**The lesson is blast radius.** One small Deployment, two replicas, and its absence
presents as *everything is broken*. When a whole cluster degrades at once, check the
shared infrastructure — DNS, the CNI, the API server — before you debug any single app.

Real-world version: CoreDNS is fine but under-provisioned, and you get *intermittent*
resolution failures under load. Far harder, same first check.
</details>

<details>
<summary><b>9 — Node DiskPressure</b></summary>

⚠️ **This one writes tens of GB to your real disk**, because kind nodes share the Docker
VM's filesystem and the kubelet's hard eviction threshold is `nodefs.available < 10%`.
The script runs a dry-run by default — it prints exactly how much it would need (30 GiB
on the machine this was written on) and does nothing until you pass `--confirm`. It
removes the file on exit, including on Ctrl-C.

**Skipping it costs you little.** You already saw the eviction *order* in Lab 3
Exercise 6, and the diagnostic commands are the part worth memorising:

```bash
kubectl describe node <node> | grep -A8 Conditions
kubectl get events -A --field-selector reason=Evicted
```

The kubelet sets `DiskPressure=True`, stops accepting new pods, and begins evicting —
**BestEffort first, then Burstable, then Guaranteed** (Lab 3, Exercise 6). Your pod was
evicted from a node that had nothing to do with your code.

**This is the one that teaches you to look at nodes, not just pods.** Most people's
`kubectl` muscle memory never leaves the namespace they're working in.
</details>

<details>
<summary><b>10 — PDB refuses a drain</b></summary>

```
error when evicting pod "api-xxx": Cannot evict pod as it would violate the
pod disruption budget.
```

**This is not a break. It's the safety net doing precisely its job** — and people file it
as a bug, which is why it's in the list.

You scaled to 1 replica; the PDB says `minAvailable: 1`; the eviction API therefore
refuses. The correct response is to **scale up so the drain can proceed**, not to delete
the PDB. Deleting the PDB to unblock a drain is how a cluster upgrade turns into an
outage.

The nuance worth having: a PDB constrains **voluntary** disruptions (drains, evictions).
It does nothing about a node that catches fire. That's what `topologySpreadConstraints`
and multiple replicas are for.

**Watch what else the drain did.** `api` was protected and stayed put — but `redis-0` and
`worker` have no PDB, so they were evicted immediately. Redis then sat `Pending` because
the node it wanted was cordoned, and every `api` pod went `0/1` as its readiness probe
failed. **The protected service was taken down by the unprotected dependency underneath
it.** A PDB on your front end buys you nothing if the datastore it depends on can be
drained out from under it — which is a far better answer than reciting the definition.
</details>

---

## Build the runbook

`RUNBOOK.md` in this folder is a template. Fill it in **in your own words** as you go.

For every symptom: **the first three commands you'd run, in order.** Three, not ten —
under interview pressure, three is what you get.

At the end, write one paragraph answering: **which of these produced no logs at all, and
how did you find them anyway?** That paragraph is the most valuable thing you'll write in
this pack, because "I'd check the logs" is what every candidate says, and roughly half of
these never produce a single application log line.

---

## What you should be able to say afterwards

Not a claim — an instinct. But if you want the sentence:

> "My triage order is state, then events, then describe, and logs come fourth — because
> a lot of Kubernetes failures never produce an application log. The container never
> started, or the problem is at a layer below the app. If pods are healthy and traffic
> still fails, I check the EndpointSlice. If everything fails at once, I check DNS and
> the CNI before I look at any single service. And I read the scheduler's message on a
> Pending pod, because it tells you exactly which nodes it rejected and why."

---

## Repeat it

Run `make random` a week later. If you can still name the break in under two minutes from
symptoms alone, it's in your hands rather than your notes — which is the only place it's
useful in an interview.
