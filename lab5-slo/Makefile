# Lab 5 — An SLO you can defend. Cost: £0, all local Docker.
SHELL := /bin/bash
.DEFAULT_GOAL := help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

up: ## Start api + redis + prometheus + alertmanager + grafana
	docker compose up --build -d
	@echo
	@echo "  API          http://localhost:8000/metrics"
	@echo "  Prometheus   http://localhost:9090"
	@echo "  Alertmanager http://localhost:9093"
	@echo "  Grafana      http://localhost:3000  (anonymous admin)"
	@echo "               -> Dashboards -> SLO -> 'Lab 5 — RED + SLO'"

down: ## Stop everything
	docker compose down -v

load: ## Drive steady traffic (leave running in its own terminal)
	./loadgen.sh http://localhost:8000/api/orders 10

## ---------- Drive the SLO ----------
break-errors: ## Inject a 10% error rate -> burn rate 20x -> fast-burn page
	INJECT_ERROR_RATE=0.10 docker compose up -d --force-recreate api
	@echo "10% errors. Burn rate ~20x. Fast-burn alert fires in ~2 min (the 'for:' clause)."
	@echo "watch: http://localhost:9090/alerts"

break-slow: ## Inject latency -> average stays flat, p99 explodes
	INJECT_SLOW_RATE=0.05 docker compose up -d --force-recreate api
	@echo "5% of requests take 0.6-3s. Compare the AVERAGE line to p99 on the D panel."

break-queue: ## Fill the queue with no worker consuming it
	@for i in $$(seq 1 60); do curl -s -o /dev/null -X POST 'localhost:8000/enqueue?n=20'; done
	@echo "1200 jobs queued, nothing consuming. WorkerQueueBacklogGrowing fires in 10 min."

fix: ## Remove all injection
	docker compose up -d --force-recreate api
	@echo "healed. Watch the 5m burn window drop immediately and the 1h window lag behind."

## ---------- Inspection ----------
rules: ## Show what Prometheus loaded (catches YAML that parses but is wrong)
	@curl -s localhost:9090/api/v1/rules | python3 -m json.tool | head -60

alerts: ## Currently firing / pending
	@curl -s localhost:9090/api/v1/alerts | \
	  python3 -c "import json,sys; [print(f\"{a['labels']['alertname']:42s} {a['state']:8s} {a['labels'].get('severity','')}\") for a in json.load(sys.stdin)['data']['alerts']] or print('(none)')"

budget: ## Error budget remaining, right now
	@curl -s --get localhost:9090/api/v1/query \
	  --data-urlencode 'query=slo:error_budget_remaining:ratio*100' | \
	  python3 -c "import json,sys; r=json.load(sys.stdin)['data']['result']; print(f\"{float(r[0]['value'][1]):.2f}% of the 30-day error budget remaining\" if r else 'no data yet — run make load for a few minutes')"

promtool: ## Validate the rule + config files (no cluster needed)
	@docker run --rm --entrypoint promtool -v "$$PWD/prometheus:/p" prom/prometheus:v3.1.0 \
	  check rules /p/rules/slo.yml
	@docker run --rm --entrypoint promtool -v "$$PWD/prometheus:/p" prom/prometheus:v3.1.0 \
	  check config /p/prometheus.yml
	@docker run --rm --entrypoint amtool -v "$$PWD/alertmanager:/a" prom/alertmanager:v0.28.0 \
	  check-config /a/alertmanager.yml

.PHONY: help up down load break-errors break-slow break-queue fix \
        rules alerts budget promtool
