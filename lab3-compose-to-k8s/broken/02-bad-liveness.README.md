# Why this patch also removes the startup probe

The first version of this file only slowed `/healthz/live` and tightened the liveness
timeout. It produced restarts — but from the **wrong probe**:

```
Normal  Killing  28s  kubelet  Container api failed startup probe, will be restarted
```

**The startup probe gates the other two.** While it is running, the liveness and readiness
probes are disabled entirely. So a slow `/healthz/live` fails *startup* first and the
container never lives long enough for liveness to matter.

That's worth knowing in its own right — it's precisely why `startupProbe` exists. A slow-
booting app (JVM, large model load, migrations) would otherwise be killed by liveness
before it ever finished starting, and the fix people reach for — a huge
`initialDelaySeconds` on liveness — delays detection of *real* hangs for the whole life of
the pod. The startup probe gives you a generous boot budget **and** a tight liveness
check afterwards.

So to demonstrate an actual **liveness** restart storm, this patch removes the startup
probe. Then:

- readiness (`/healthz/ready`) stays fast → the pod goes **Ready** and **serves traffic**
- liveness (`/healthz/live`) is slow → the kubelet kills it every ~5 seconds

A pod that is `1/1 Ready`, serving real requests, and being killed on a timer. That is the
outage, and the application is completely healthy throughout.
