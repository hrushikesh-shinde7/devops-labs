# DevOps labs

Six hands-on labs covering the delivery path: a supply-chain-hardened CI pipeline, Terraform
module design, a Compose → Kubernetes migration, Gateway API, SLO and burn-rate alerting, and
deliberate failure injection.

**These were built to be run, not read.** Running them surfaced **eleven real defects** in my own
manifests, Terraform and alerting rules — which is the reason the repo exists. A lab that has
never been executed teaches you the shape of a thing; a lab that has been executed teaches you
where it breaks.

Five of the six cost nothing to run. Everything is local except one deliberately fenced-off
Terraform environment that creates real cloud resources.

---

## The labs

| | Lab | What it covers | Cost |
|---|---|---|---|
| 1 | [`lab1-secure-pipeline`](lab1-secure-pipeline/) | A CI pipeline with **no standing credentials** — OIDC workload identity federation instead of a stored service-principal secret, plus image signing and SBOM generation | **£0** |
| 2 | [`lab2-terraform`](lab2-terraform/) | Module design, **remote state with locking**, reading a plan and `# forces replacement`, `moved`/`import` blocks, drift detection | **£0** in `envs/practice` |
| 3 | [`lab3-compose-to-k8s`](lab3-compose-to-k8s/) | Translating a Compose stack to Kubernetes — Deployments, Services, ConfigMaps/Secrets, PVCs, probes and **graceful shutdown** | **£0** (kind) |
| 4 | [`lab4-gateway-api`](lab4-gateway-api/) | **Gateway API**, prompted by the Ingress-NGINX end-of-life — `Gateway`/`HTTPRoute`, and `ingress2gateway` for migration | **£0** |
| 5 | [`lab5-slo`](lab5-slo/) | Prometheus, Grafana and Alertmanager — **multi-window burn-rate alerting**, grouping, inhibition | **£0** |
| 6 | [`lab6-break-things`](lab6-break-things/) | Breaking a running cluster on purpose and diagnosing it — the one worth repeating | **£0** |

**Only `lab2-terraform/envs/dev` spends money.** It builds real infrastructure and is fenced
behind its own directory with loud warnings. `envs/practice` teaches the part that actually
matters — state, locking, drift, `for_each` versus `count` — for nothing, because *the expensive
lessons in Terraform are about state, not about the cloud provider*.

If you do run `envs/dev`: **`terraform destroy` the same day.**

---

## Running them

See [`GUIDE.md`](GUIDE.md) for prerequisites, suggested order and per-lab detail. In short:

```bash
cd lab3-compose-to-k8s && make cluster deploy   # labs 3, 4 and 6 share this one cluster
```

Order matters a little: **lab 3 before lab 2's `envs/dev`**, because kind is free and the cloud
is not.

---

## A few things these labs are opinionated about

Each is defended in the lab that raises it:

- **Config is injected at deploy, not baked at build.** The artifact you tested should be the
  artifact that ships.
- **No standing credentials in CI.** Workload identity federation rather than a stored secret —
  there is then nothing to leak or rotate (lab 1).
- **A Kubernetes `Secret` is base64, not encryption.** Fine for a local cluster; say so out loud
  rather than implying otherwise (lab 3).
- **Terraform state contains every attribute in plaintext**, including generated passwords.
  `sensitive = true` only masks CLI output. So state is never committed, and read access to the
  backend *is* secret access (lab 2).
- **Alert on symptoms, not causes.** High CPU with healthy latency is not an incident (lab 5).
- **Deliberate failure is the only honest test of a runbook.** Lab 6 exists because a recovery
  procedure nobody has performed is a hypothesis.

---

## What this is not

It is **self-directed learning**, not production experience. The clusters are local, the scale is
small, and nothing here has served real traffic. My production work is elsewhere and under NDA.

What it *is*: evidence that I can stand up this tooling, read its failure modes, and recover from
them — and that when I say I understand something, I have run it.

---

## Licence

MIT. Use any of it.
