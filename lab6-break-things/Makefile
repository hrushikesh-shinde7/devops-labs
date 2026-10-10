# Lab 6 — Break things on purpose. Cost: £0. Needs the Lab 3 kind cluster.
SHELL := /bin/bash
NS := lab3
.DEFAULT_GOAL := help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

check: ## Verify the Lab 3 cluster is up
	@kubectl -n $(NS) get deploy api >/dev/null 2>&1 \
	  || { echo "✗ run 'make cluster deploy' in ../lab3-compose-to-k8s first"; exit 1; }
	@echo "✓ ready"

b1: check  ## ImagePullBackOff
	@./breaks/01-image-pull.sh
b2: check  ## OOMKilled, exit 137
	@./breaks/02-oom.sh
b3: check  ## Liveness restart storm
	@./breaks/03-liveness-storm.sh
b4: check  ## CreateContainerConfigError (bad secret key)
	@./breaks/04-bad-secret-key.sh
b5: check  ## Pending — unschedulable
	@./breaks/05-unschedulable.sh
b6: check  ## Service with no endpoints
	@./breaks/06-selector-typo.sh
b7: check  ## Full PVC
	@./breaks/07-fill-pvc.sh
b8: check  ## Total DNS failure
	@./breaks/08-kill-coredns.sh
b9: check  ## Node DiskPressure + evictions
	@./breaks/09-node-pressure.sh
b10: check ## PDB refuses a drain (the safety net working)
	@./breaks/10-pdb-blocks-drain.sh

random: check ## Pick one at random — no peeking at which
	@N=$$((RANDOM % 10 + 1)); \
	 echo "running break #$$N — diagnose it before you look"; \
	 ./breaks/$$(printf '%02d' $$N)-*.sh

## ---------- The three commands that start every diagnosis ----------
triage: ## Run them, in order, and read them in order
	@echo "=== 1. what state is everything in? ==="
	@kubectl -n $(NS) get pods -o wide
	@echo; echo "=== 2. what did the cluster TRY to do? ==="
	@kubectl -n $(NS) get events --sort-by=.lastTimestamp | tail -20
	@echo; echo "=== 3. why is this specific pod unhappy? ==="
	@POD=$$(kubectl -n $(NS) get pod -l app=api -o name | head -1); \
	 kubectl -n $(NS) describe $$POD | sed -n '/Containers:/,/^Events/p' | head -40

why: ## Last-state + exit code of the api pod — the OOM/crash tell
	@kubectl -n $(NS) get pod -l app=api -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .status.containerStatuses[*]}  state:     {.state}{"\n"}  lastState: {.lastState}{"\n"}  restarts:  {.restartCount}{"\n"}{end}{end}' | python3 -c "import sys;print(sys.stdin.read().replace(chr(39),chr(34)))"

endpoints: ## The check for "healthy pods, failing traffic"
	@kubectl -n $(NS) get endpointslice -l kubernetes.io/service-name=api -o wide
	@echo "(empty ADDRESSES = the Service selector matches no pod)"

reset: ## Undo EVERY break
	-kubectl -n kube-system scale deploy coredns --replicas=2
	-kubectl -n $(NS) exec redis-0 -- rm -f /data/filler 2>/dev/null
	-@for n in $$(kubectl get nodes -o name | cut -d/ -f2); do \
	   docker exec $$n rm -f /filler 2>/dev/null; kubectl uncordon $$n 2>/dev/null; done
	@# Delete the Deployments outright rather than re-applying over them.
	@# A broken rollout DEADLOCKS: maxUnavailable:0 means the controller may
	@# not scale the broken ReplicaSet down (available would drop below
	@# desired), and maxSurge:1 means it may not scale the good one up
	@# (it would exceed the pod ceiling). Nothing moves, and `kubectl apply`
	@# of the correct spec does NOT rescue it. That is a real deadlock worth
	@# recognising -- in production you break it with `rollout undo`, or by
	@# deleting the failed ReplicaSet.
	-kubectl -n $(NS) delete deploy api worker --ignore-not-found --wait=true
	kubectl apply -f ../lab3-compose-to-k8s/k8s/
	kubectl -n $(NS) rollout status deploy/api --timeout=180s
	kubectl -n $(NS) rollout status deploy/worker --timeout=180s
	@echo "✓ reset"

.PHONY: help check b1 b2 b3 b4 b5 b6 b7 b8 b9 b10 random triage why endpoints reset
