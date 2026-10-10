# Lab 3 — Compose to Kubernetes. Cost: £0 (everything runs locally in kind).
SHELL   := /bin/bash
CLUSTER := lab3
NS      := lab3
IMAGE   := lab3-api:local

.DEFAULT_GOAL := help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

## ---------- Part 1: the BEFORE state ----------
compose-up: ## Run the stack the old way (docker compose)
	docker compose -f compose/docker-compose.yml up --build -d
	@echo "→ http://localhost:8000/healthz/ready"

compose-down: ## Stop the Compose stack
	docker compose -f compose/docker-compose.yml down -v

## ---------- Part 2: the AFTER state ----------
build: ## Build the image
	docker build -t $(IMAGE) .

cluster: ## Create the kind cluster (3 nodes)
	kind create cluster --name $(CLUSTER) --config kind-config.yaml

load: build ## Load the local image into kind (no registry needed)
	kind load docker-image $(IMAGE) --name $(CLUSTER)

deploy: load ## Apply all manifests
	kubectl apply -f k8s/
	kubectl -n $(NS) rollout status deploy/api --timeout=120s
	kubectl -n $(NS) rollout status deploy/worker --timeout=120s
	@echo "→ http://localhost:8080/healthz/ready"

metrics: ## Install metrics-server (needed for the HPA)
	kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
	kubectl -n kube-system patch deploy metrics-server --type=json \
	  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
	kubectl -n kube-system rollout status deploy/metrics-server --timeout=120s

## ---------- Inspection ----------
status: ## What is actually running
	@kubectl -n $(NS) get pods,svc,endpointslice,hpa,pdb -o wide

qos: ## Show the QoS class of every pod (Exercise 6)
	@kubectl -n $(NS) get pods -o custom-columns='NAME:.metadata.name,QOS:.status.qosClass'

break-qos: ## Exercise 6: strip resources -> BestEffort -> evicted first
	kubectl -n $(NS) patch deploy api --type=json --patch-file broken/03-besteffort.json
	kubectl -n $(NS) rollout status deploy/api --timeout=120s
	@$(MAKE) --no-print-directory qos

logs: ## Tail the api logs
	kubectl -n $(NS) logs -l app=api --tail=50 -f

events: ## Recent events, newest last — your first debugging stop
	kubectl -n $(NS) get events --sort-by=.lastTimestamp

load-test: ## Drive CPU so the HPA scales up
	@echo "Watch in another terminal: kubectl -n $(NS) get hpa api -w"
	kubectl -n $(NS) run loadgen --rm -it --restart=Never --image=busybox:1.36 -- \
	  /bin/sh -c 'while true; do wget -q -O- http://api/queue; done'

## ---------- Breaking things on purpose ----------
break-oom: ## Exercise 5: shrink the memory limit, then curl /burn?mb=400
	kubectl -n $(NS) patch deploy api --patch-file broken/01-oomkilled.yaml
	@echo "now: curl 'localhost:8080/burn?mb=400' ; make status"

break-liveness: ## Exercise 4: cause a restart storm with a healthy app
	kubectl -n $(NS) patch deploy api --type=json --patch-file broken/02-bad-liveness.json
	@echo "now: kubectl -n $(NS) get pods -w   (watch RESTARTS climb on a READY pod)"

break-selector: ## Exercise 7: silent zero-endpoint Service
	kubectl apply -f broken/04-selector-mismatch.yaml
	@echo "now: kubectl -n $(NS) get endpointslice -l kubernetes.io/service-name=api"

fix: ## Undo every break
	kubectl apply -f k8s/
	kubectl -n $(NS) set env deploy/api SLOW_MODE=false
	kubectl -n $(NS) rollout status deploy/api --timeout=120s

## ---------- Teardown ----------
clean: ## Delete the cluster (everything is local; nothing to pay for)
	kind delete cluster --name $(CLUSTER)

.PHONY: help compose-up compose-down build cluster load deploy metrics \
        status qos logs events load-test break-oom break-liveness \
        break-selector break-qos fix clean
