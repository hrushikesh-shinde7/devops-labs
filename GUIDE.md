# Hands-On Labs

Working starter files for the six labs in `../src/12_Hands_On_Labs.md`. Everything is
scaffolded — you run the labs rather than spend the evening setting them up.

> **A thing you've built survives a follow-up question. A thing you've read does not.**
> That's the entire argument for this folder. Every lab ends with a paragraph you can
> actually say in an interview, and every one of those paragraphs is only true if you
> ran the lab.

---

## Cost — read this first

| Lab | Cost | Notes |
|---|---|---|
| 1 — Secure pipeline | **£0** | GitHub Actions free tier + local Docker. The OIDC setup is free too. |
| 2 — Terraform | **£0** for `envs/practice` | `envs/dev` creates **real Azure resources**. AKS + ACR + Key Vault ≈ **₹250–400/day**. |
| 3 — Compose → K8s | **£0** | Local kind cluster. |
| 4 — Gateway API | **£0** | Runs on the Lab 3 cluster. |
| 5 — SLO | **£0** | Local Docker: Prometheus + Grafana + Alertmanager. |
| 6 — Break things | **£0** | Runs on the Lab 3 cluster. |

**Only Lab 2's `envs/dev` can cost money.** It is fenced off behind its own directory and
loud warnings, and `envs/practice` teaches the part that actually matters — state, drift,
`for_each` vs `count` — for nothing. *The expensive lessons in Terraform are about state,
not about Azure.*

If you do run `envs/dev`: **`terraform destroy` the same day.** An AKS cluster left
running over a weekend is a genuinely unpleasant bill.

---

## Suggested order

This matches `12_Hands_On_Labs.md` §Suggested order, with one change: **do Lab 3 before
Lab 2's `envs/dev`**, because kind is free and Azure is not.

| Week | Labs | Why |
|---|---|---|
| **1** | **Lab 2** (`envs/practice` only) · **Lab 1** | Terraform is your biggest gap. Lab 1 is a half-day quick win that closes supply-chain and CI auth. |
| **2** | **Lab 3** · **Lab 4** | Kubernetes is the centrepiece. Lab 4 is a live 2026 question most candidates can't answer. |
| **3** | **Lab 5** · **Lab 6** | SLOs are the highest-signal ops topic. Lab 6 is the one to repeat. |

Labs 3, 4 and 6 share one kind cluster. Create it once:

```bash
cd lab3-compose-to-k8s && make cluster deploy
```

---

## The labs

### `lab1-secure-pipeline/` — a pipeline with no standing credentials
GitHub Actions: multi-stage non-root image, `syft` SBOM, `trivy` gate, `cosign` keyless
signing, workload identity federation via Terraform, plus a Kyverno policy that **refuses
unsigned images** — because a signature nobody verifies is worth nothing.
**Key exercise:** swap in vulnerable pins and watch the scan fail the build.

### `lab2-terraform/` — the gap that matters most
Two tracks. `envs/practice` (**free**, `random`/`local` providers only) teaches plan/apply,
state, drift, `state mv`, and `count` vs `for_each` through six numbered exercises.
`envs/dev` (**costs money**) builds RG → ACR → AKS → Key Vault with real modules.
**Key exercise:** change something in the portal, then run `plan` and read the drift.

### `lab3-compose-to-k8s/` — the migration, and what breaks
The same api + worker + redis stack in Compose and then in Kubernetes, with a
translation table for every Compose concept. Deployment, Service, StatefulSet with PVC,
ConfigMap, Secret, all three probes, HPA, PDB, NetworkPolicy.
**Key exercises:** liveness restart storm · OOMKilled · QoS classes · the silent
zero-endpoint Service.

### `lab4-gateway-api/` — Ingress-NGINX is EOL
The legacy Ingress with its vendor annotations, then Envoy Gateway with GatewayClass →
Gateway → HTTPRoute, header-based routing, and a weighted 90/10 split.
**Key insight:** the role split is organisational, not technical — infra owns the Gateway,
app teams own their routes. And the Ingress *API* isn't going away; the *controller* is.

### `lab5-slo/` — an SLO you can defend
An instrumented API, Prometheus with recording rules, multi-window multi-burn-rate
alerts, Alertmanager severity routing, and a Grafana RED dashboard that plots the
average alongside p99 **on purpose**.
**Key exercises:** watch the average lie · watch the error budget drain · watch a
burn-rate alert resolve honestly after a fix.

### `lab6-break-things/` — the one to repeat
Ten scripted failures on the Lab 3 cluster, a triage harness, and a runbook template to
fill in yourself. `make random` picks one without telling you which.
**Key lesson:** events before logs — roughly half of these never produce an application
log line at all.

---

## What to do with the output

Two things, and the second is worth more than it looks:

1. **Fill in `lab6-break-things/RUNBOOK.md` in your own words.** Symptom → the first
   three commands, in order. That's the artefact you'll actually recall under pressure.

2. **Write one short public post** about whichever surprised you most — the restart
   storm, or the Terraform state drift. Not a tutorial; a short "here's what I expected,
   here's what happened." That post is what answers *"can this person work
   independently?"* for a remote hiring manager, and it's the cheapest credibility you
   will ever buy.

   Post it from your personal account. It's technical content, not a job-search signal —
   which is exactly why it's safe to publish while you're still employed.

---

## Prerequisites

```bash
brew install kind kubectl helm terraform syft trivy cosign
docker info          # Docker Desktop or colima must be running
```

Not everything is needed for every lab; each lab's README says what it needs.

## Verification status

Everything here has been run, not just written.

| Checked | How |
|---|---|
| Terraform (3 root modules) | `terraform validate` + `terraform fmt` clean; the free practice env applied, destroyed, and its `count` vs `for_each`, drift and plaintext-state exercises confirmed |
| Prometheus rules + config | `promtool check rules` (15 rules) and `check config` |
| Alertmanager config | `amtool check-config` — route, 1 inhibit rule, 3 receivers |
| Dockerfiles (labs 1, 3, 5) | all build; all run as UID 10001; lab 3 verified under `--read-only` |
| Lab 5 metrics | `/metrics` serves the RED metrics with a real `le="0.5"` bucket |
| Lab 3 on a real cluster | 3-node kind cluster; all 12 manifests applied; api + worker + redis verified end to end |
| Lab 3 exercises 4–8 | every one reproduced and its documented symptom confirmed |
| Lab 6 breaks | run against the live cluster; `make reset` verified to recover from each |
| Lab 4 end to end | Envoy Gateway installed on kind; GatewayClass, Gateway and all 3 HTTPRoutes attached; basic, header-canary and weighted routes verified by counting which pod served each request |
| `ingress2gateway` | run against the legacy Ingress; its 4 warnings and its output reviewed |

**Eleven real bugs were found and fixed this way** — a crash-looping worker, two patches
that reported success while changing nothing, a break rejected by the API server, a break
the cluster couldn't perform, a `reset` that deadlocked, a helm CRD ownership conflict, a
missing GatewayClass, a `kubectl wait` that could never succeed, a NetworkPolicy that
blocked its own canary, and a missing route filter. Most became lessons in the READMEs,
because the failure was more instructive than the fix.

One documented claim was also **wrong and is now corrected**: kind's default CNI
*does* enforce NetworkPolicy as of kind 0.33.

**Not executed:** Lab 2's `envs/dev` (real Azure spend), Lab 1's GitHub Actions workflow
and cosign signing (needs a pushed repo), and Lab 6's break 09 (would write ~30 GB).
Those are yours to run.

If a lab doesn't work first time, debugging it *is* Lab 6.
