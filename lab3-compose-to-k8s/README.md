# Lab 3 — Compose → Kubernetes

**Cost: £0.** Everything runs locally in [kind](https://kind.sigs.k8s.io/). No cloud account.
**Time: ~3 hours** for Part 1 + Part 2, another ~2 hours for the breakage exercises.
**Companion doc:** `../../docx/03_Kubernetes.docx`, `../../docx/12_Hands_On_Labs.docx`.

---

## Why this lab exists

You already run multi-container apps with Compose. The interview question is never
"what is a Pod" — it is some version of **"walk me through moving a Compose stack to
Kubernetes, and tell me what breaks."** That is a question about probes, resource
limits, QoS, and Service selectors, and you can only answer it convincingly if you
have watched each one fail.

So: Part 1 runs the stack in Compose. Part 2 runs the *same* stack in Kubernetes.
Part 3 breaks it four ways on purpose.

---

## The app

Three components, deliberately shaped like a real one:

| Component | What it is | Why it's here |
|---|---|---|
| `api` | FastAPI, HTTP, stateless | The thing that needs replicas, probes, a Service |
| `worker` | Redis queue consumer, no HTTP | The thing that needs **no** Service and **no** readiness probe |
| `redis` | Stateful, needs a volume | The thing that needs a StatefulSet, not a Deployment |

Endpoints: `/healthz/live`, `/healthz/ready`, `/enqueue?n=`, `/queue`, `/burn?mb=`.

---

## Prerequisites

```bash
brew install kind kubectl          # macOS
docker info                        # Docker Desktop / colima must be running
```

---

## Part 1 — the BEFORE state (20 min)

```bash
make compose-up
curl localhost:8000/healthz/ready
curl -X POST 'localhost:8000/enqueue?n=5'
docker compose -f compose/docker-compose.yml logs worker
make compose-down
```

Before moving on, write down the answers — you will be asked these:

1. What happens to the queue if `redis` restarts? (Hint: check the `volumes:` key.)
2. How do you run two `api` containers? What breaks when you try?
3. If `api` hangs but the process is still alive, what recovers it?

Compose's answers are, in order: *the volume survives*, *you can't — the host port
collides*, and *nothing*. Those last two are the reason Kubernetes exists.

---

## Part 2 — the AFTER state (90 min)

```bash
make cluster       # 3-node kind cluster, ~90s
make deploy        # builds, loads the image, applies k8s/
make status
curl localhost:8080/healthz/ready
```

### The translation table — memorise this

| Compose | Kubernetes | The thing that is actually different |
|---|---|---|
| `services:` entry | Deployment | A **control loop**, not a process. It converges toward desired state forever. |
| `ports: ["8000:8000"]` | Service | Compose binds a host port (one per host). A Service is a **virtual IP + DNS name** with load balancing. |
| `environment:` | ConfigMap | Config becomes a **separate object** with its own lifecycle. Changing it does not restart pods by itself. |
| secrets in `.env` | Secret | Still only base64. See §Secrets below. |
| `volumes:` named volume | PVC / `volumeClaimTemplate` | Storage is **claimed**, not declared, and it's scheduled — a RWO volume pins the pod to one node. |
| `restart: unless-stopped` | `restartPolicy` + probes | Compose restarts on **exit**. Kubernetes also restarts on **unhealthy**, which is a much bigger claim. |
| `depends_on` | *(nothing)* | There is no ordering. Pods must tolerate their dependencies being absent — see §Startup ordering below. |
| `deploy.replicas` | `replicas:` + HPA | Actual horizontal scaling, on a metric. |
| — | PodDisruptionBudget | Survives node drains. No Compose equivalent. |
| — | NetworkPolicy | Compose networks are all-open. So is Kubernetes, until you write one. |

### The three probes — the highest-yield 10 minutes in this lab

| Probe | Question | On failure | Put a dependency check in it? |
|---|---|---|---|
| `startupProbe` | "Has it finished booting?" | Holds off the other two | No |
| `livenessProbe` | "Is it wedged?" | **Restarts the container** | **Never.** See below. |
| `readinessProbe` | "Should it get traffic?" | Removes it from the Service endpoints | Yes — that's the point |

**The rule you must be able to state out loud:** a liveness probe that checks a
dependency converts *"the database is slow"* into *"every pod in the fleet is
restarting."* It turns a partial outage into a total one. Liveness checks only
the process; readiness checks whether it can usefully serve.

Read `k8s/04-api-deployment.yaml` — the probes are commented inline.

### Startup ordering — the thing Compose did for you

Kubernetes has **no `depends_on`**. Pods start in whatever order the scheduler picks,
and a worker will routinely come up before Redis has DNS, let alone a ready pod.

Read `app/worker.py`. The naive version — which is what most people write first — was:

```python
while True:
    job = r.brpop("jobs", timeout=5)      # ConnectionError on iteration 1
```

That exits 1, so the container `CrashLoopBackOff`s until Redis happens to come up. It
does eventually work, which is exactly why it survives code review. But it burns restart
budget, it fills the logs with stack traces that look like a real incident, and the
backoff delay grows to **five minutes** — so a two-second Redis blip can cost you a
five-minute worker outage.

The version in the repo retries with exponential backoff and reconnects if Redis
disappears mid-flight. Prove it to yourself by deploying the worker *first*, on purpose:

```bash
kubectl -n lab3 delete deploy worker statefulset redis
kubectl apply -f k8s/05-worker-deployment.yaml     # worker first
sleep 6
kubectl apply -f k8s/03-redis-statefulset.yaml     # redis second
kubectl -n lab3 get pods -l app=worker             # RESTARTS: 0
kubectl -n lab3 logs -l app=worker
```

Note it gives up after 120 seconds rather than retrying forever. **An infinite retry
hides a genuinely broken config behind a `Running` pod**, which is worse than crashing —
at least a crash is visible.

**Tolerating an absent dependency is the pod's job, not the platform's.** That sentence is
the whole answer to "how do you handle service startup order in Kubernetes."

---

### Requests vs limits

```
requests  -> what the SCHEDULER reserves. Too high = pods won't fit. Too low = noisy neighbours.
limits    -> what the KERNEL enforces.
              memory over limit -> SIGKILL, OOMKilled, no grace, no logs
              cpu over limit    -> throttled (slow), never killed
```

Which is why `k8s/03-redis-statefulset.yaml` sets a memory limit and **no CPU limit** —
CPU throttling of a latency-sensitive service is a classic self-inflicted slowdown.

---

## Part 3 — break it on purpose (2 hrs)

Each of these is a real outage someone has had. Run it, diagnose it from the
cluster (not from this README), then read the explanation in the manifest comment.

### Exercise 4 — the liveness restart storm

```bash
make break-liveness
watch -n2 "kubectl -n lab3 get pods -l app=api"     # RESTARTS climbs
kubectl -n lab3 get events --field-selector reason=Killing --sort-by=.lastTimestamp
make fix
```

Watch the cycle. Each pod:

1. starts, passes readiness in ~2s, goes **`1/1 Ready`**
2. **serves real traffic for about 18 seconds**
3. is killed by the kubelet
4. restarts, and does it all again — roughly every 24 seconds, forever

Measured on this exact setup: **25 requests over 25 seconds → 16 succeeded, 9 failed.**
A steady ~35% error rate, permanently, on an application that is working perfectly.

```
Warning  Unhealthy  Liveness probe failed: ... context deadline exceeded
Normal   Killing    Container api failed liveness probe, will be restarted
```

The app never broke. **`timeoutSeconds: 1` against a handler that takes 10s is the entire
outage.** And because every replica shares the cause, they all fail together — a probe
misconfiguration is one of the few things that can take down an entire fleet at once.

**Say it out loud: "the probe was the bug."**

#### The startup-probe detail that makes this work

`broken/02-bad-liveness.json` also **removes** the startup probe, and that's not
incidental. **While a startup probe is running, liveness and readiness are disabled
entirely.** With it in place, a slow `/healthz/live` fails *startup* first — the event
says `failed startup probe` — and the container never lives long enough for liveness to
matter at all.

Which is exactly why `startupProbe` exists: a slow-booting app (JVM, model load,
migrations) needs a generous boot budget *and* a tight liveness check afterwards. The fix
people reach for instead — a large `initialDelaySeconds` on liveness — delays detection
of genuine hangs for the entire life of the pod. Full note in
`broken/02-bad-liveness.README.md`.

### Exercise 5 — OOMKilled

```bash
make break-oom
curl 'localhost:8080/burn?mb=400'
kubectl -n lab3 get pods            # OOMKilled -> CrashLoopBackOff
kubectl -n lab3 describe pod -l app=api | grep -A5 'Last State'
make fix
```

Note what you did **not** get: a log line, a stack trace, a graceful shutdown.
Exit code 137 = 128 + 9 (SIGKILL). Reason: `OOMKilled`. That's all the evidence
there ever is.

### Exercise 6 — QoS class, and a patch that lies to you

```bash
make qos                            # Burstable
make break-qos                      # BestEffort
make fix
```

Eviction order under node memory pressure: **BestEffort → Burstable → Guaranteed**.
"We set no resource requests" and "we get evicted first" are the same sentence.

**There's a second lesson hidden in this one.** The obvious way to write this patch —
a strategic-merge `resources: {}` — prints `deployment.apps/api patched` and **changes
nothing**, because a merge patch merges and an empty map merges to no change. You only
find out by checking the result. Deleting a field needs a JSON Patch with an explicit
`remove` op, which is why `broken/03-besteffort.json` is JSON and everything else in
that folder is YAML. Full explanation in `broken/03-besteffort.README.md`.

Worth knowing because a green "patch" step in CI that silently did nothing is a genuinely
nasty class of bug.

### Exercise 7 — the silent one

```bash
make break-selector
curl localhost:8080/healthz/ready    # connection refused
kubectl -n lab3 get pods             # everything Running, 0 restarts
kubectl -n lab3 get endpointslice -l kubernetes.io/service-name=api
make fix
```

No error, no event, no failing probe — just an empty EndpointSlice. Make
`get endpointslice` your reflex when pods are healthy and traffic still fails.

### Exercise 8 — rollout and rollback

```bash
kubectl -n lab3 set image deploy/api api=lab3-api:does-not-exist
kubectl -n lab3 rollout status deploy/api --timeout=60s   # fails
kubectl -n lab3 get pods                                  # old pods STILL SERVING
kubectl -n lab3 rollout undo deploy/api
```

`maxUnavailable: 0` is why the bad image never took traffic. This is the single
best answer to "how do you do safe deploys" before you get to blue/green.

### Exercise 9 — the HPA

```bash
make metrics
make load-test                       # in one terminal
kubectl -n lab3 get hpa api -w       # in another
```

Watch it scale to 6, then watch it take five minutes to come back down —
that's `stabilizationWindowSeconds: 300`, deliberately asymmetric. Scaling up
fast is cheap; scaling down fast causes flapping.

---

## Secrets — read this before you copy anything here into real work

`k8s/02-secret.yaml` is base64, which is **encoding, not encryption**. Anyone with
`get secret` in the namespace reads it in plaintext, and it sits unencrypted in etcd
unless the cluster enables encryption-at-rest. It is fine for a local kind cluster
and nothing else.

Real options, in the order you'd reach for them: the **Secrets Store CSI driver**
with Azure Key Vault (your stack), **External Secrets Operator**, or **SOPS** for
GitOps. Covered in `09_Security_Secrets_SupplyChain.md`.

---

## NetworkPolicy caveat

`k8s/08-networkpolicy.yaml` applies cleanly but kind's default CNI (kindnet)
**does not enforce it** — the policy is accepted and silently ignored. That is
itself worth knowing: a NetworkPolicy is only as real as your CNI. To see it
actually enforced, create the cluster with `--config kind-config.yaml` plus
`disableDefaultCNI: true` and install Cilium or Calico.

---

## What you should be able to say afterwards

Rehearse these out loud (see `31_Think_Aloud_Playbook`):

1. "A Deployment is a control loop, not a process manager."
2. "Liveness restarts, readiness de-registers. Never check a dependency in liveness."
3. "Requests are for the scheduler, limits are for the kernel. Memory limits kill; CPU limits throttle."
4. "No requests means BestEffort means evicted first."
5. "Healthy pods and failing traffic means look at the EndpointSlice."
6. "`maxUnavailable: 0` means a bad image never serves a request."

---

## Teardown

```bash
make clean          # deletes the kind cluster
```

Nothing in this lab costs money, so there is no billing risk — but the cluster
does hold ~2 GB of RAM. Delete it when you're done for the day.
