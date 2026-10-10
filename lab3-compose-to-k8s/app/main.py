"""Tiny FastAPI service shaped like the real one: API + worker + Redis."""
import os
import time

import redis
from fastapi import FastAPI, Response

app = FastAPI()
r = redis.from_url(os.getenv("REDIS_URL", "redis://redis:6379/0"))

STARTED = time.monotonic()
SLOW_MODE = os.getenv("SLOW_MODE", "false").lower() == "true"


@app.get("/healthz/live")
def live() -> dict:
    """Liveness: cheap, NO dependency checks.

    LAB EXERCISE: set SLOW_MODE=true to make this slow, then watch
    the liveness probe cause a restart storm. That is the classic outage.
    """
    if SLOW_MODE:
        time.sleep(10)
    return {"status": "alive"}


@app.get("/healthz/ready")
def ready(response: Response) -> dict:
    """Readiness: MAY check dependencies — failing here de-registers, not restarts."""
    try:
        r.ping()
    except redis.RedisError as exc:
        response.status_code = 503
        return {"status": "not ready", "reason": str(exc)}
    return {"status": "ready", "uptime_s": round(time.monotonic() - STARTED, 1)}


@app.post("/enqueue")
def enqueue(n: int = 1) -> dict:
    for _ in range(n):
        r.lpush("jobs", f"job-{time.time()}")
    return {"queued": n, "depth": r.llen("jobs")}


@app.get("/queue")
def queue_depth() -> dict:
    return {"depth": r.llen("jobs")}


@app.get("/burn")
def burn(mb: int = 100) -> dict:
    """LAB EXERCISE: allocate memory to trigger OOMKilled."""
    _ = bytearray(mb * 1024 * 1024)
    time.sleep(30)
    return {"allocated_mb": mb}
