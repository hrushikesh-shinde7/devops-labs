# Lab 5 — An SLO you can defend

**Cost: £0.** Everything runs in local Docker.
**Time: ~1 day.**
**Companion docs:** `../../docx/07_Observability_and_SRE.docx`, `../../docx/12_Hands_On_Labs.docx` (Lab 5),
and `../../../Interview_Prep/docx/21_Observability_and_SRE.docx`.

---

## Why this one matters most

Observability and SRE is the **highest-signal ops topic in a lead interview**, because it's
where engineering judgment shows. Anyone can list "logs, metrics, traces." Very few
candidates can explain why they alert on a burn rate instead of an error rate, and fewer
still have watched an error budget actually drain.

By the end of this lab you will have watched it drain.

---

## The SLO

| | |
|---|---|
| **SLI** | proportion of `/api/orders` requests that do not return 5xx |
| **SLO** | 99.5% over a rolling 30 days |
| **Error budget** | 0.5% → about **3 h 39 m** of total unavailability per 30 days |

That last number is the one that changes conversations. "99.5%" sounds abstract;
"three and a half hours a month, and we've used two of them" is a decision.

---

## Run it

```bash
make up          # api, redis, prometheus, alertmanager, grafana
make load        # leave this running in its own terminal
```

Then open **Grafana at http://localhost:3000** → Dashboards → SLO → *Lab 5 — RED + SLO*.

Give it five minutes of traffic before anything means much. Ratio metrics on low
traffic are wildly noisy — three errors out of four requests is a 75% error rate, and
that's a real way people fool themselves on small services.

---

## Exercise 1 — averages hide the tail (30 min)

```bash
make break-slow      # 5% of requests take 0.6–3s
```

Watch the **D — Duration** panel. The dashboard deliberately plots the **average**
alongside p50/p95/p99. The average barely moves. p99 goes through the roof.

> **A 200 ms average with a 4-second p99 means one request in a hundred is unusable —
> and the average will never tell you.**

For a user hitting 20 endpoints to render one page, "one request in a hundred" is not a
rare event; it's most page loads touching at least one slow call. That's the tail-latency
amplification argument, and it's the reason histograms exist.

**Why a histogram and not a summary:** histogram buckets are counters, so they **aggregate
across instances**. You can sum buckets from 50 pods and compute a true fleet-wide p99.
Pre-computed quantiles (a summary) cannot be averaged — an average of p99s is not a p99
of anything. Say that and you've ended the question.

**The bucket choice is the real decision.** You can only compute quantiles at bucket
boundaries, so `prometheus/rules/slo.yml` and `app/main.py` both carry an explicit `0.5`
bucket because the latency SLO threshold is 500 ms. Pick buckets after you pick the SLO,
never before.

> **⚠️ And the modern answer, which is what an interviewer wants next.** Native histograms
> went **stable in Prometheus v3.8.0**: exponential buckets computed automatically, sparse
> storage, and **one series per metric instead of one per bucket**. They largely remove the
> bucket-guessing problem entirely.
>
> **This lab uses classic histograms on purpose.** Almost every running system and every
> classic exporter still emits them, and `histogram_quantile()` over `le` buckets is what
> you'll be asked to write. Learn the old way here; know that native histograms are the
> answer to *"what would you change?"* — and that they're stable but **not on by default
> until Prometheus v4**, so you must set `scrape_native_histograms: true` yourself.
> *(Doc 07 §3 has the comparison table.)*

```bash
make fix
```

---

## Exercise 2 — burn rate, not threshold (60 min)

```bash
make break-errors     # 10% errors -> burn rate ~20x
make alerts           # watch it go pending, then firing
make budget
```

Open http://localhost:9090/alerts and watch `OrdersAPIErrorBudgetFastBurn` sit in
**pending** for two minutes (the `for:` clause) before firing.

### The arithmetic, which you should be able to do out loud

```
burn rate  = observed error ratio / (1 - SLO)
           = 0.10 / 0.005
           = 20x
```

At 20× you exhaust a 30-day budget in **36 hours**. That deserves a page.

**14.4× is the canonical fast-burn threshold** because 14.4 × (1/30 days) consumes 2% of
the budget in one hour — and exhausts the whole thing in about two days.

| Burn | Long window | Short window | Budget spent | Action |
|---|---|---|---|---|
| 14.4× | 1 h | 5 m | 2% in 1 h | **Page** |
| 6× | 6 h | 30 m | 5% in 6 h | **Page** |
| 3× | 1 d | 2 h | 10% in 1 d | Ticket |
| 1× | 3 d | 6 h | sustained overspend | Ticket |

### Why every alert pairs two windows

The **long window** answers *"is this real?"* — it's slow but trustworthy.
The **short window** answers *"is it still happening?"*

Without the short window, an alert that fires from a 1-hour window keeps firing for an
hour after you've fixed the problem. Engineers learn that alerts lie, and then they stop
reading them. **The short window exists to make the alert resolve honestly.**

Prove it to yourself:

```bash
make fix
make alerts        # watch the 5m window collapse first, the 1h window lag behind
```

Compare against the naive alternative — `error_rate > 1% for 5m`. That pages at 3am for a
30-second blip that consumed 0.001% of the budget, and it does **not** page for a slow
0.7% bleed that will miss the SLO by the 20th of the month. It is wrong in both directions.

### The other half: severity routing

Look at `alertmanager/alertmanager.yml`. `severity: page` and `severity: ticket` route to
different receivers, with different `repeat_interval`s, and there's an inhibit rule so the
medium-burn alert stays quiet while the fast-burn one is already paging.

**A ticket-severity alert that can reach a phone is a page.** If everything pages, people
stop answering, and that's how real incidents get missed. The routing tree is where the
severity label stops being decoration.

---

## Exercise 3 — the leading indicator (20 min)

```bash
make break-queue      # 1200 jobs, nothing consuming
```

`WorkerQueueBacklogGrowing` uses `worker_queue_depth > 500 AND deriv(...) > 0` — depth
alone is a false positive during a normal burst. **Depth plus a positive slope** means
consumers are genuinely not keeping up.

For an async pipeline, **queue lag moves before anything user-facing breaks**. It's the
alert that lets you fix things during business hours. Mention it and you've shown you
think about async systems, not just request/response.

---

## Exercise 4 — the alert everyone forgets (10 min)

```bash
docker compose stop api
make alerts           # OrdersAPITargetDown
```

Every SLO query above returns **no data** when the target is gone — and in PromQL,
"no data" does not fire a `>` comparison. **An outage can look exactly like silence.**
`up{job="api"} == 0` is the alert that closes that hole, and forgetting it is one of the
most common real gaps in otherwise-good monitoring.

```bash
docker compose start api
```

---

## Recording rules — the operational detail

`sli:http_errors:ratio_rate5m` and friends exist so the dashboard doesn't re-scan raw
samples on every refresh. Six burn windows over 30 days of data will time out a dashboard
built on raw queries. The naming convention `level:metric:operation` is the Prometheus
standard, and using it correctly is a small, cheap credibility signal.

Validate them without a running stack:

```bash
make promtool
```

---

## What you should be able to say afterwards

> "I instrument with RED — rate, errors, and duration as histograms, because averages
> hide the tail users actually feel. I set an SLO, derive an error budget from it, and
> alert on **burn rate** rather than raw error rate, so we page when the budget is
> genuinely at risk rather than on every blip. Each alert pairs a long window for
> confidence with a short window so it resolves honestly once we've fixed it. For an
> async pipeline I add queue lag as a leading indicator — that's usually where trouble
> shows before anything user-facing breaks. And I always add a `target down` alert,
> because no-data isn't the same as healthy."

**If pushed on the organisational side:** the error budget is the point. It converts
"are we reliable enough?" from an argument into a number, and it gives you an agreed rule
for what happens when the budget is gone — reliability work takes priority over features
until it's back. That agreement has to exist *before* an incident, not during one.

---

## Teardown

```bash
make down
```
