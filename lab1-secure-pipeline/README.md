# Lab 1 — A pipeline with no standing credentials

**Cost: £0** for everything in Part 1 and 2. The optional Azure federation setup is also
free (app registrations and federated credentials cost nothing); only what you *deploy*
would cost money, and this lab deploys nothing.
**Time: ~half a day.**
**Companion docs:** `../../docx/09_Security_Secrets_SupplyChain.docx`, `../../docx/04_CI_CD_Pipelines.docx`.

---

## Why do this one first

It's half a day, and it touches three things interviewers reliably probe: **image
hygiene**, **supply chain**, and **how your pipeline authenticates**.

The third is the one most candidates get wrong. They still paste a service-principal
client secret into a CI variable and call it done. Being able to say *"our pipeline has
no standing cloud credentials"* — and then explain the mechanism — separates you
immediately.

---

## Part 1 — run the whole pipeline locally (60 min)

```bash
make tools          # syft, trivy, cosign
make build
make nonroot
make scan
make sbom-inspect
```

### What `make nonroot` is checking

Read the `Dockerfile`. Two things are deliberate:

1. **Multi-stage** — the venv is built in a stage that is thrown away. The shipped image
   has no `pip`, no compiler, no build tooling. That's not just size: a compiler inside a
   running container is a tool you've handed to anyone who gets a shell.
2. **`USER 10001`, a number, not a name.** Kubernetes' `runAsNonRoot: true` check reads
   the numeric UID from the image config. An image whose `USER` is a *name* the kubelet
   can't resolve gets **rejected at admission** with `CreateContainerConfigError`. This
   catches people out constantly.

### What `make sbom-inspect` is showing you

It prints your declared dependencies, then the component count in the actual image.
**Know that ratio for your own service.** "Two direct dependencies, ~130 components in the
image" is a concrete, slightly alarming number that makes a very good interview aside —
and it's the honest argument for why SBOMs exist. You cannot patch what you don't know
you're shipping.

---

## Part 2 — watch the scan fail (45 min)

The point is not the green tick. **You want to have seen the failure.**

```bash
make break-deps
make build
make scan          # non-zero exit. Read the CVE list.
make fix-deps
```

`app/requirements-vulnerable.txt` pins three genuinely old, genuinely vulnerable
packages. Look at what trivy reports — the CVE ID, the installed version, the fixed
version, the severity.

Then look at two flags in `.github/workflows/build.yml` and understand why both are there:

- **`exit-code: "1"`** — without this, trivy reports and the build goes green anyway.
  A scanner that cannot fail a build is a report nobody reads.
- **`ignore-unfixed: true`** — don't block a deploy on a CVE that has no patch available.
  Without it, one unfixable base-image CVE blocks every deploy, and within a week someone
  disables the scanner entirely. **A gate that can't be satisfied gets removed.**

Notice the workflow scans **twice**: the source tree before building, and the image
after. Source scanning misses everything the base image brings with it — which is usually
where most of the CVEs actually live.

---

## Part 3 — keyless signing, and what it actually proves (60 min)

Push the repo to GitHub and let the workflow run, or read the `sbom-and-sign` job.

### The mechanism, in the order it happens

1. The runner asks GitHub for an **OIDC token** describing itself — repo, ref, workflow,
   actor. This needs `permissions: id-token: write`.
2. `cosign` sends that token to **Fulcio**, Sigstore's CA, which issues a certificate
   valid for about **ten minutes**, binding the signing key to that identity.
3. cosign signs the image digest, then records the signature and certificate in
   **Rekor** — a public, append-only **transparency log**.
4. **The private key is discarded.** It existed for seconds and was never stored.

### What it proves and what it doesn't

> ⚠️ **Understand before you claim.** If you can't explain what a transparency log is for,
> don't mention cosign in an interview.

**Proves:** this exact digest was built by *that* workflow, in *that* repo, on *that* ref.
Provenance of the **builder**.

**Does not prove:** that the code is any good, reviewed, or free of vulnerabilities.
Provenance is not quality.

**What the transparency log is for:** the certificate expired in ten minutes, so at
verification time you can't ask the CA "is this still valid?" Rekor's countersigned,
append-only entry proves the signature existed *while the certificate was valid*. It also
means a compromised identity's signatures are **publicly discoverable** — you can query
the log and find every artifact signed under it. The log makes misuse detectable rather
than silent. Short-lived certificates plus a public log is the whole design.

```bash
make verify REF=ghcr.io/YOUR_ORG/YOUR_REPO@sha256:...
make rekor  REF=ghcr.io/YOUR_ORG/YOUR_REPO@sha256:...
```

Always verify by **digest**, never by tag. A tag is a mutable pointer; `:latest` can be
repointed at something else a minute after you verified it. The digest is the artifact.

### Signing means nothing until something refuses unsigned images

`policy/verify-before-deploy.yaml` is a Kyverno `ClusterPolicy` that rejects Pods whose
images aren't signed by your workflow identity. **A signature nobody verifies has bought
you nothing.** Apply it to the Lab 3 kind cluster:

```bash
helm install kyverno kyverno/kyverno -n kyverno --create-namespace
kubectl apply -f policy/verify-before-deploy.yaml
```

Roll it out as `Audit` first, look at what it *would* have blocked, then switch to
`Enforce`. Going straight to Enforce on a live cluster is how you break every deploy in
the org at 9am.

---

## Part 4 — workload identity federation (45 min)

This is the part that earns the claim.

Read `terraform/oidc.tf`. The security model is one field:

```hcl
subject = "repo:myorg/myrepo:ref:refs/heads/main"
```

Entra ID accepts a token only when the `sub` claim matches **exactly**. There is no
secret. Nothing to rotate, nothing to leak in a log, nothing an ex-employee keeps a copy
of.

### The failure mode to be able to name

```hcl
subject = "repo:myorg/myrepo:*"        # trusts every pull_request — from every FORK
subject = "repo:myorg/*:ref:refs/..."  # trusts every repo in the org
```

Both have caused real breaches. **The wildcard is the vulnerability, not OIDC.** A
`pull_request` from a fork runs attacker-authored workflow code; if that context can mint
a production cloud token, you have handed the subscription to anyone who can open a PR.

Scoping to a GitHub **environment** (`:environment:production`) is stronger than scoping
to a branch, because an environment can require reviewers — the approval gate becomes
part of the authentication path rather than a UI convenience.

Note `AZURE_CLIENT_ID` is a repo **variable**, not a secret. It's a public identifier;
treating it as a secret suggests you think it's the thing protecting you. It isn't — the
federated subject is.

```bash
make oidc ORG=yourorg REPO=yourrepo RG=your-rg
```

The role assignment is scoped to **one resource group**. `Contributor` at subscription
scope is the most common over-grant in Azure CI, and it converts any pipeline compromise
into a full-subscription compromise.

---

## What you should be able to say afterwards

> "My pipeline has no standing cloud credentials — it authenticates with workload
> identity federation, so there's no secret to leak or rotate. The federated subject is
> pinned to a specific repo and environment, because a wildcard there would trust every
> fork's pull request. Every image is multi-stage and non-root, ships with an SBOM, and
> is signed with cosign keyless — which proves the builder's identity via a short-lived
> Fulcio cert and a Rekor transparency-log entry, not that the code is good. The build
> fails on high-severity CVEs, with unfixed ones excluded so the gate stays satisfiable.
> And there's an admission policy that rejects unsigned images, because a signature
> nobody verifies isn't worth anything."

**If asked what you'd do first at a new company:** turn the scanner on in report-only
mode and look at the number before proposing a gate. You cannot fail builds on a backlog
nobody has triaged — you'd just get the gate turned off.

---

## The 2026 context worth knowing

The **EU Cyber Resilience Act** makes SBOMs a legal requirement, not a best practice —
reporting obligations from **September 2026**, full compliance by **December 2027**.
If you're building software sold into the EU, "we generate an SBOM" stops being a nice
line on a slide. Being aware of that timeline is a differentiator right now, because
most candidates aren't.

---

## Teardown

```bash
make clean
# and if you ran `make oidc`:  cd terraform && terraform destroy
```
