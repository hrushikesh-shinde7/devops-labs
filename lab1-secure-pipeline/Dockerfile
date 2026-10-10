# syntax=docker/dockerfile:1
#
# Multi-stage: the build toolchain never reaches the shipped image. That is
# not just size — a compiler in a running container is an attacker's tool.
FROM python:3.11-slim AS builder
WORKDIR /build
COPY app/requirements.txt .
RUN python -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

FROM python:3.11-slim AS runtime

# Non-root with an explicit high UID. `USER nobody` is not enough — Kubernetes'
# runAsNonRoot check reads the numeric UID, and an image whose USER is a *name*
# the kubelet cannot resolve will be rejected at admission.
RUN groupadd --gid 10001 app && \
    useradd --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app
COPY --chown=app:app app/ ./
USER 10001
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD python -c "import urllib.request;urllib.request.urlopen('http://localhost:8000/healthz')" || exit 1

ENTRYPOINT ["uvicorn"]
CMD ["main:app", "--host", "0.0.0.0", "--port", "8000"]
