# Personal Runbook — symptom → first three commands

Fill this in **as you go**, in your own words. Do not copy the answers from the README
until you've tried. This is the artefact you'll actually recall under interview
pressure — and it's the direct answer to *"walk me through how you'd debug this."*

The discipline that makes it work: **for every symptom, write the first three commands
you'd run, in order, and what each one would tell you.** Three, not ten. Under pressure
you get three.

---

## Template

### Symptom: `________`

| # | Command | What it tells me |
|---|---|---|
| 1 | | |
| 2 | | |
| 3 | | |

**Root cause was:**
**The tell that gave it away:**
**What I'd have checked first next time:**

---

## Your entries

### Symptom: ImagePullBackOff

| # | Command | What it tells me |
|---|---|---|
| 1 | | |
| 2 | | |
| 3 | | |

**Root cause was:**
**The tell:**

---

### Symptom: Pod restarting, RESTARTS climbing

| # | Command | What it tells me |
|---|---|---|
| 1 | | |
| 2 | | |
| 3 | | |

**Root cause was:**
**The tell:**

---

### Symptom: Pod stuck Pending

| # | Command | What it tells me |
|---|---|---|
| 1 | | |
| 2 | | |
| 3 | | |

**Root cause was:**
**The tell:**

---

### Symptom: Pods Running and Ready, but traffic fails

| # | Command | What it tells me |
|---|---|---|
| 1 | | |
| 2 | | |
| 3 | | |

**Root cause was:**
**The tell:**

---

### Symptom: Container never starts, no application logs at all

| # | Command | What it tells me |
|---|---|---|
| 1 | | |
| 2 | | |
| 3 | | |

**Root cause was:**
**The tell:**

---

### Symptom: Everything in the cluster is failing at once

| # | Command | What it tells me |
|---|---|---|
| 1 | | |
| 2 | | |
| 3 | | |

**Root cause was:**
**The tell:**

---

## The meta-lesson to write down at the end

After all ten, write one paragraph answering: **which failures produced no logs, and how
did you find them anyway?** That paragraph is the most useful thing in this lab, because
"I check the logs" is what every candidate says, and half of these break types never
produce a single application log line.
