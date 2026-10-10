# Lab 4 — Gateway API and the Ingress-NGINX EOL

**Cost: £0.** Runs on the kind cluster from Lab 3.
**Time: ~half a day.**
**Prerequisite: Lab 3 must be deployed** (`make cluster deploy` in `../lab3-compose-to-k8s`).
**Companion doc:** `../../docx/12_Hands_On_Labs.docx` (Lab 4), `../../docx/08_Networking_for_DevOps.docx`.

---

## Why this lab is worth more than its size

This is a **live 2026 question that most candidates cannot answer**, which makes it
disproportionately valuable. Ingress-NGINX reached end of life in **March 2026** — no
patches, no security updates — following a joint statement from the Kubernetes Steering
Committee and the Security Response Committee. Roughly **half of cloud-native
environments** were affected. Most shops have this migration in flight or overdue, so
asking about it tells an interviewer whether you read release notes or not.

### The nuance almost everyone gets wrong

> **The Ingress API is not removed.** It is GA and feature-frozen. What retired is the
> community *controller*, `kubernetes/ingress-nginx`. Development moved to **Gateway API**.

If you say "Ingress is deprecated," you're wrong and a good interviewer will know.
Say: *"the API is frozen, the community controller is EOL."*

---

## The thing to actually understand: the role split

Gateway API's real design point is **organisational, not technical**.

| Resource | Owned by | Answers |
|---|---|---|
| `GatewayClass` | Infrastructure / platform | "What kind of proxy do we run?" |
| `Gateway` | Infrastructure / platform | "What listeners, ports, TLS and hostnames exist?" |
| `HTTPRoute` | **Application team** | "How does *my* traffic get routed?" |

Ingress conflated all three into one object that everybody had to edit — which is why
route changes needed a platform-team review, and why two teams could silently claim the
same hostname. Gateway's `allowedRoutes` (see `gateway/01-gateway.yaml`) makes that
delegation explicit and enforceable.

**Say that in an interview and you've shown you understand *why* it exists, not just its syntax.**

---

## Run it

### Step 1 — look at the legacy Ingress (10 min)

```bash
make ingress
```

Read `ingress/legacy-ingress.yaml`. Count the things that are *not portable*:

- `nginx.ingress.kubernetes.io/rewrite-target` — vendor annotation
- `nginx.ingress.kubernetes.io/proxy-body-size` — vendor annotation
- `pathType: ImplementationSpecific` — an explicit "each controller may differ" escape hatch

That's the whole problem in one file: behaviour encoded as **untyped strings** that the
API server cannot validate. Get an annotation name wrong and nothing errors — it just
silently doesn't apply.

No controller is installed, so `ADDRESS` stays empty. That is deliberate: the object is
still accepted by the API server. The API is fine. The controller is the thing that died.

### Step 2 — install Gateway API and Envoy Gateway (20 min)

```bash
make gateway
```

This installs the **Gateway API CRDs** (they are not built into Kubernetes — they ship
as CRDs on their own release cadence, in `standard` and `experimental` channels), then
**Envoy Gateway**, then the GatewayClass and the Gateway.

Three things here bite in practice, and all three are in the Makefile for a reason.

#### Who owns the CRDs

`helm install` **fails** if you installed the CRDs yourself first:

```
Error: failed to install CRD crds/gatewayapi-crds.yaml: conflict occurred ...
Apply failed with 2 conflicts: conflicts with "kubectl-client-side-apply":
  - .metadata.annotations.gateway.networking.k8s.io/channel
  - .spec.versions
```

The chart bundles **its own copy** of the Gateway API CRDs, and two owners cannot both
manage the same object. Hence `--skip-crds`. **Whoever installs the CRDs owns them**, and
you generally want that to be you, not an application chart — you pin the version and the
channel, and controllers come and go underneath. It's the same argument as owning your
own Terraform state.

#### The chart does *not* create a GatewayClass

`helm get manifest eg | grep -c "kind: GatewayClass"` → **0**. Without one, a Gateway is
never scheduled and nothing tells you why in an obvious place. `gateway/00-gatewayclass.yaml`
is applied, not just read.

#### `Programmed` never goes True on kind — and that's fine

```
Accepted=True    (Accepted)
Programmed=False (AddressNotAssigned)
```

Envoy Gateway creates its proxy Service as type `LoadBalancer`. kind has no
load-balancer controller, so `EXTERNAL-IP` stays `<pending>` forever and the Gateway
honestly reports that it has no address.

**The dataplane is completely fine.** Look one level down:

```bash
make listeners
```
```
Listener-level:
  Programmed=True   Accepted=True   ResolvedRefs=True
```

Gateway-level `Programmed` is about *reachability from outside*; listener-level conditions
are about *whether routing is configured*. On kind you get the second without the first,
and you reach it by port-forward. `make gateway` therefore waits on `Accepted` — waiting
on `Programmed` would hang forever.

### Step 3 — attach a route (15 min)

```bash
make routes
make port-forward          # leave running
make test                  # in another terminal
```

`make routes` also applies `routes/00b-networkpolicy-canary.yaml`, and the reason is
worth 60 seconds of your time.

Lab 3's NetworkPolicy allows Redis ingress only from `app: api` and `app: worker`. The
canary is `app: api-canary`, so its Redis traffic is dropped and it never goes Ready.
The symptom:

```
Readiness probe failed: Get "http://10.244.1.7:8000/healthz/ready":
context deadline exceeded (Client.Timeout exceeded while awaiting headers)
```

**A timeout — not "connection refused".** NetworkPolicy *drops* packets; it does not
reject them:

| Symptom | Cause |
|---|---|
| `context deadline exceeded` / hangs | packets **dropped** — NetworkPolicy, security group, firewall |
| `connection refused` | packets **rejected** — nothing listening, wrong port, crashed process |

Those point at completely different causes, and telling them apart instantly is one of
the more useful reflexes you can build.

> **Correction to Lab 3's README, found by running this:** kind's default CNI (kindnet)
> **does** enforce NetworkPolicy as of kind 0.33. Older guidance — including an earlier
> version of Lab 3's README — says it silently ignores it. Verified here: the canary was
> blocked, `app: api` was not.

### Step 4 — run the conversion tool (20 min)

```bash
brew install ingress2gateway     # or: go install github.com/kubernetes-sigs/ingress2gateway@latest
make convert
```

It handles the mechanical translation. **The interesting part is what it refuses to
translate** — that's the list of things that were only ever nginx behaviour, never
Ingress semantics. Run against `ingress/legacy-ingress.yaml`, it emits four warnings:

```
WARN  Failed to apply ..."nginx.ingress.kubernetes.io/rewrite-target":
      Path rewrites with capture group references are not supported
WARN  Failed to apply ..."nginx.ingress.kubernetes.io/proxy-body-size":
      Most Gateway API implementations have reasonable body size and buffering defaults
WARN  Ingress NGINX serves TLS ... with a self-signed certificate.
      This behavior will not be translated
INFO  Using case-insensitive regex path matches. You may want to change this.
```

and generates:

```yaml
  rules:
  - backendRefs:
    - name: api
      port: 80
    matches:
    - path:
        type: RegularExpression
        value: (?i)/api(/|$)(.*).*
```

**Read that rule carefully. There is no `filters:` block.**

The rewrite was dropped, so the backend receives `/api/queue` instead of `/queue`. Deploy
that and your app returns 404 while every Gateway API status field says
`Accepted=True, ResolvedRefs=True` — because routing genuinely is fine. The tool told you,
in a warning you will scroll past.

Two more things it did that you'd want to review: it turned
`pathType: ImplementationSpecific` into a **case-insensitive regex** (`(?i)`), quietly
changing matching semantics; and it generated a Gateway with `gatewayClassName: nginx`,
which won't exist on your cluster.

> **`ingress2gateway` gets you 80% of the way and is confident about the other 20%.**
> Treat its output as a first draft to review, never as a migration. That sentence is a
> good answer on its own.

### Step 5 — routing Ingress could never do cleanly (30 min)

```bash
make routes-advanced
make test
```

- **Header-based** (`routes/02-httproute-header.yaml`) — canary by `x-canary: true`
- **Weighted 90/10** (`routes/03-httproute-weighted.yaml`) — the feature people install
  an entire service mesh to obtain. It's core Gateway API, and it's what Argo Rollouts
  and Flagger drive underneath for progressive delivery.

Measured on this lab, counting which pod actually logged each request:

```
10 requests WITH  x-canary:true  ->  api:+0   canary:+10
10 requests WITHOUT               ->  api:+10  canary:+0
40 requests, weighted 90/10       ->  api:+36  canary:+4
```

**Note the filter on *both* rules in `02-httproute-header.yaml`.** Filters are
per-**rule**, not per-route. Omit it on the canary rule and you get this:

```
$ curl -i -H 'x-canary: true' .../api/queue
HTTP/1.1 404 Not Found
server: uvicorn
```

Routing worked; the canary received `/api/queue` unrewritten and 404'd on its own.
**The `server:` header is the tell** — `envoy` means the gateway rejected it, `uvicorn`
means your app did, so the request arrived and the problem is the path, not the route.
That one header saves you an hour.

Rule precedence is **defined by the spec** (exact path beats prefix, longer prefix beats
shorter, then method, then header count) rather than left to each controller's
interpretation. Under Ingress, precedence was implementation-defined — which is exactly
why migrating between controllers used to break routing in surprising ways.

---

## Diagnostics — the part that pays off

```bash
make status
```

Gateway API puts real machine-readable status on every object. When a route doesn't
work, you don't read controller logs — you read conditions:

| Condition | Where | Means |
|---|---|---|
| `Accepted` | Gateway | The spec is valid |
| `Programmed` | Gateway | A real dataplane is actually configured |
| `ResolvedRefs` | Gateway / HTTPRoute | Every backend and secret it references exists |
| `Accepted` | HTTPRoute | The parent Gateway allowed this route to attach |

**`ResolvedRefs: False` with reason `BackendNotFound`** is the single most common
failure, and it's a whole class of Ingress bug — "traffic 503s and nothing tells you why" —
that is now a readable status field. **`Accepted: False` / `NotAllowedByListeners`** means
the Gateway's `allowedRoutes` rejected you: the delegation boundary working as designed.

---

## What you should be able to say afterwards

> "Ingress-NGINX went end-of-life in March 2026, so any cluster still on it is running an
> unpatched, internet-facing proxy. The migration path is Gateway API — and the nuance is
> that the Ingress API itself isn't going away, it's the community controller that retired.
> I've done the conversion with Envoy Gateway, and `ingress2gateway` handles most of the
> mechanical translation. The part I like is the role split: infra owns the GatewayClass
> and Gateway, app teams own their own HTTPRoutes, so route changes stop needing a
> platform-team review. And the status conditions are a real operational improvement —
> `ResolvedRefs: BackendNotFound` tells you in one line what used to be an afternoon of
> reading nginx logs."

**If asked what you'd actually do at work:** run both in parallel. Install Gateway API
alongside the existing Ingress controller, move one low-traffic service, watch it for a
week, then migrate the rest by hostname. Don't cut over at the edge in one change — the
edge is the one place where a rollback has to work.

---

## Teardown

```bash
make clean      # removes this lab, leaves the Lab 3 cluster running
```
