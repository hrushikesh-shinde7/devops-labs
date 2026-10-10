# Lab 4 — Gateway API. Cost: £0. Runs on the Lab 3 kind cluster.
SHELL   := /bin/bash
NS      := lab3
CLUSTER := lab3
EG_VER  := v1.2.6

.DEFAULT_GOAL := help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

check: ## Verify the Lab 3 cluster is up
	@kubectl config current-context | grep -q 'kind-$(CLUSTER)' \
	  || { echo "✗ Lab 3 cluster not active. Run 'make cluster deploy' in ../lab3-compose-to-k8s"; exit 1; }
	@kubectl -n $(NS) get deploy api >/dev/null 2>&1 \
	  || { echo "✗ Lab 3 api not deployed. Run 'make deploy' in ../lab3-compose-to-k8s"; exit 1; }
	@echo "✓ Lab 3 cluster ready"

## ---------- Step 1: the legacy way ----------
ingress: check ## Apply the classic Ingress (READ it, don't expect it to serve)
	kubectl apply -f ingress/legacy-ingress.yaml
	kubectl -n $(NS) describe ingress api-legacy
	@echo
	@echo "Note: no ingress-nginx controller is installed, so ADDRESS stays empty."
	@echo "That is the point — the API object exists; the controller is EOL."

## ---------- Step 2: install Gateway API + Envoy Gateway ----------
crds: ## Install the Gateway API CRDs (standard channel)
	kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
	kubectl get crd | grep gateway.networking.k8s.io

# --skip-crds is REQUIRED, not optional. The gateway-helm chart bundles its own
# copy of the Gateway API CRDs, and installing them on top of the ones `make
# crds` already applied fails with a field-manager ownership conflict:
#
#   Error: failed to install CRD crds/gatewayapi-crds.yaml: conflict occurred
#   ... Apply failed with 2 conflicts: conflicts with "kubectl-client-side-apply"
#   - .metadata.annotations.gateway.networking.k8s.io/channel
#   - .spec.versions
#
# Whoever installs the CRDs owns them. We do, deliberately -- see README
# "Who owns the CRDs".
gateway: crds ## Install Envoy Gateway and create the Gateway
	helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
	  --version $(EG_VER) -n envoy-gateway-system --create-namespace --skip-crds
	kubectl -n envoy-gateway-system rollout status deploy/envoy-gateway --timeout=180s
	@# The chart does NOT create a GatewayClass (verified: 0 in `helm get
	@# manifest`). Without one, a Gateway never gets scheduled at all.
	kubectl apply -f gateway/00-gatewayclass.yaml
	kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=60s
	kubectl apply -f gateway/01-gateway.yaml
	@# Waits for Accepted, NOT Programmed. On kind, Programmed never becomes
	@# True: the proxy Service is type LoadBalancer and there is no LB
	@# controller, so the Gateway reports AddressNotAssigned forever. The
	@# dataplane is fine -- check the LISTENER conditions, not the Gateway's.
	kubectl -n $(NS) wait --for=condition=Accepted gateway/lab-gateway --timeout=180s
	@$(MAKE) --no-print-directory listeners

## ---------- Step 3-5: routes ----------
routes: ## Apply the canary backend + all three HTTPRoutes
	kubectl apply -f routes/00-canary-backend.yaml
	@# Without this the canary cannot reach Redis and never goes Ready.
	kubectl apply -f routes/00b-networkpolicy-canary.yaml
	kubectl -n $(NS) rollout status deploy/api-canary --timeout=120s
	kubectl apply -f routes/01-httproute-basic.yaml
	kubectl -n $(NS) get httproute api-route -o yaml | grep -A12 'parents:'

routes-advanced: ## Header-based + weighted routes
	kubectl apply -f routes/02-httproute-header.yaml
	kubectl apply -f routes/03-httproute-weighted.yaml
	kubectl -n $(NS) get httproute

## ---------- Testing ----------
port-forward: ## Forward the Envoy listener to localhost:8888
	@GW=$$(kubectl -n $(NS) get gateway lab-gateway \
	  -o jsonpath='{.status.addresses[0].value}' 2>/dev/null); \
	SVC=$$(kubectl -n envoy-gateway-system get svc \
	  -l gateway.envoyproxy.io/owning-gateway-name=lab-gateway -o name | head -1); \
	echo "forwarding $$SVC -> localhost:8888"; \
	kubectl -n envoy-gateway-system port-forward $$SVC 8888:80

test: ## Hit every route (run port-forward in another terminal first)
	@echo "--- basic route ---"
	@curl -s -w ' [HTTP %{http_code}]\n' -H 'Host: lab3.localdev.me' localhost:8888/api/queue
	@echo "--- header canary (should hit api-canary) ---"
	@curl -s -w ' [HTTP %{http_code}]\n' -H 'Host: lab3.localdev.me' -H 'x-canary: true' localhost:8888/api/queue
	@echo "--- unknown host (should be 404 from envoy) ---"
	@curl -s -o /dev/null -w '  HTTP %{http_code} (envoy rejected it — no route for that host)\n' \
	  -H 'Host: nope.localdev.me' localhost:8888/api/queue
	@echo "--- weighted 90/10: which backend served each of 40 requests? ---"
	@# /queue, not / -- the app has no route at / and would 404, which looks
	@# like a routing failure and is not one.
	@before_a=$$(kubectl -n $(NS) logs -l app=api --tail=-1 2>/dev/null | grep -c 'GET /queue'); \
	 before_c=$$(kubectl -n $(NS) logs -l app=api-canary --tail=-1 2>/dev/null | grep -c 'GET /queue'); \
	 for i in $$(seq 1 40); do \
	   curl -s -o /dev/null -H 'Host: canary.localdev.me' localhost:8888/queue; done; \
	 sleep 3; \
	 after_a=$$(kubectl -n $(NS) logs -l app=api --tail=-1 2>/dev/null | grep -c 'GET /queue'); \
	 after_c=$$(kubectl -n $(NS) logs -l app=api-canary --tail=-1 2>/dev/null | grep -c 'GET /queue'); \
	 echo "  api: $$((after_a-before_a))   canary: $$((after_c-before_c))   (expect ~36 / ~4)"

listeners: ## Listener conditions — the real signal on kind
	@echo "Gateway-level (AddressNotAssigned is EXPECTED on kind):"
	@kubectl -n $(NS) get gateway lab-gateway -o jsonpath='{range .status.conditions[*]}  {.type}={.status} ({.reason}){"\n"}{end}'
	@echo "Listener-level (this is what tells you routing works):"
	@kubectl -n $(NS) get gateway lab-gateway -o jsonpath='{range .status.listeners[*].conditions[*]}  {.type}={.status} ({.reason}){"\n"}{end}'

status: ## Gateway + route status — where the real diagnostics live
	@echo "=== GatewayClass ==="; kubectl get gatewayclass
	@echo; echo "=== Gateway ==="; kubectl -n $(NS) get gateway -o wide
	@echo; echo "=== Conditions (read these when a route does not attach) ==="
	@kubectl -n $(NS) get gateway lab-gateway -o jsonpath='{range .status.conditions[*]}{.type}{"\t"}{.status}{"\t"}{.message}{"\n"}{end}'
	@echo; echo "=== HTTPRoutes ==="; kubectl -n $(NS) get httproute
	@for r in $$(kubectl -n $(NS) get httproute -o name); do \
	  echo "--- $$r ---"; \
	  kubectl -n $(NS) get $$r -o jsonpath='{range .status.parents[*].conditions[*]}{.type}{"\t"}{.status}{"\t"}{.reason}{"\n"}{end}'; \
	done

## ---------- Step 4: the conversion tool ----------
convert: ## Run ingress2gateway over the legacy Ingress and diff it
	@command -v ingress2gateway >/dev/null || { \
	  echo "install: brew install ingress2gateway"; \
	  echo "      or: go install github.com/kubernetes-sigs/ingress2gateway@latest"; exit 1; }
	ingress2gateway print --input-file=ingress/legacy-ingress.yaml --providers=ingress-nginx \
	  > /tmp/lab4-generated.yaml
	@echo "=== generated ==="; cat /tmp/lab4-generated.yaml
	@echo; echo "=== now compare with what you wrote by hand ==="
	@echo "diff <(cat /tmp/lab4-generated.yaml) routes/01-httproute-basic.yaml"

clean: ## Remove everything this lab added (leaves Lab 3 intact)
	-kubectl delete -f routes/ --ignore-not-found
	-kubectl delete -f gateway/01-gateway.yaml --ignore-not-found
	-kubectl delete -f ingress/legacy-ingress.yaml --ignore-not-found
	-helm uninstall eg -n envoy-gateway-system

.PHONY: help check ingress crds gateway routes routes-advanced \
        listeners port-forward test status convert clean
