"""Trivial queue consumer — stands in for a Celery worker.

Note the retry loop. Kubernetes has NO equivalent of Compose's `depends_on`:
pods start in whatever order the scheduler picks, and this worker will
routinely come up before Redis has DNS, let alone a ready pod.

The naive version of this file was:

    while True:
        job = r.brpop("jobs", timeout=5)

...which raises ConnectionError on the first iteration and exits 1, so the
container CrashLoopBackOffs until Redis happens to be up. It "works" — the
restart eventually succeeds — but it's noise in the logs, it burns restart
budget, and on a bad day the backoff delay (up to 5 minutes) is much longer
than the outage that caused it.

Tolerating an absent dependency is the pod's job, not the platform's.
"""
import os
import sys
import time

import redis

REDIS_URL = os.getenv("REDIS_URL", "redis://redis:6379/0")
r = redis.from_url(REDIS_URL, socket_connect_timeout=2)


def wait_for_redis(max_wait: int = 120) -> None:
    """Block until Redis answers, with backoff. Fail loudly if it never does."""
    deadline = time.monotonic() + max_wait
    delay = 0.5
    while time.monotonic() < deadline:
        try:
            r.ping()
            print(f"connected to {REDIS_URL}", flush=True)
            return
        except redis.RedisError as exc:
            print(f"waiting for redis ({exc}); retrying in {delay:.1f}s", flush=True)
            time.sleep(delay)
            delay = min(delay * 2, 10)
    # Give up eventually — an infinite retry hides a genuinely broken config
    # behind a Running pod, which is worse than crashing.
    print(f"redis unreachable after {max_wait}s, exiting", file=sys.stderr, flush=True)
    sys.exit(1)


if __name__ == "__main__":
    print("worker started", flush=True)
    wait_for_redis()

    while True:
        try:
            job = r.brpop("jobs", timeout=5)
        except redis.RedisError as exc:
            # Redis restarted underneath us. Reconnect rather than die.
            print(f"lost redis ({exc}); reconnecting", flush=True)
            wait_for_redis()
            continue

        if job:
            print(f"processing {job[1].decode()}", flush=True)
            time.sleep(0.5)
