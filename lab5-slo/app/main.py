"""Lab 3's API, instrumented for RED. The only new thing is /metrics."""
import os
import random
import time

import redis
from fastapi import FastAPI, Request, Response
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
)

app = FastAPI()
r = redis.from_url(os.getenv("REDIS_URL", "redis://redis:6379/0"))

# --- RED. Three metrics, and only three. ---------------------------------
# R(ate) and E(rrors) come from one counter: rate() gives you requests/sec,
# and filtering by status gives you the error rate. Don't make two counters.
REQUESTS = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "path", "status"],
)

# D(uration) as a HISTOGRAM, never a gauge and never an average.
# The buckets are the decision that matters: you can only compute quantiles at
# bucket boundaries, so put a boundary near your SLO threshold. Ours is 500ms,
# hence an explicit 0.5 bucket.
LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency",
    ["method", "path"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0),
)

# The leading indicator. For an async system, queue lag moves BEFORE anything
# user-facing breaks — which is what makes it worth paging on.
QUEUE_DEPTH = Gauge("worker_queue_depth", "Jobs waiting in the queue")

ERROR_RATE = float(os.getenv("INJECT_ERROR_RATE", "0"))    # 0.0 - 1.0
SLOW_RATE = float(os.getenv("INJECT_SLOW_RATE", "0"))


@app.middleware("http")
async def observe(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    elapsed = time.perf_counter() - start

    # Use the ROUTE TEMPLATE, not the raw URL. `/order/{id}` is one label value;
    # `/order/12345` is a new time series per order — that is how you cardinality-
    # bomb a Prometheus and take down your own monitoring.
    route = request.scope.get("route")
    path = getattr(route, "path", "__unmatched__")

    REQUESTS.labels(request.method, path, response.status_code).inc()
    LATENCY.labels(request.method, path).observe(elapsed)
    return response


@app.get("/metrics")
def metrics() -> Response:
    try:
        QUEUE_DEPTH.set(r.llen("jobs"))
    except redis.RedisError:
        pass
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/healthz/live")
def live() -> dict:
    return {"status": "alive"}


@app.get("/healthz/ready")
def ready(response: Response) -> dict:
    try:
        r.ping()
    except redis.RedisError as exc:
        response.status_code = 503
        return {"status": "not ready", "reason": str(exc)}
    return {"status": "ready"}


@app.get("/api/orders")
def orders(response: Response) -> dict:
    """The SLI endpoint. Error and latency injection drive the lab."""
    if random.random() < SLOW_RATE:
        time.sleep(random.uniform(0.6, 3.0))     # straddles the 500ms bucket
    if random.random() < ERROR_RATE:
        response.status_code = 500
        return {"error": "injected"}
    time.sleep(random.uniform(0.01, 0.08))
    return {"orders": random.randint(1, 50)}


@app.post("/enqueue")
def enqueue(n: int = 1) -> dict:
    for _ in range(n):
        r.lpush("jobs", f"job-{time.time()}")
    return {"queued": n, "depth": r.llen("jobs")}
