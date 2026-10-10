# Lab 1 — A pipeline with no standing credentials.
# Cost: £0 for everything except the optional Azure deploy job.
SHELL := /bin/bash
IMAGE := lab1-api:local
.DEFAULT_GOAL := help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

tools: ## Install syft, trivy, cosign (macOS)
	brew install syft trivy cosign

## ---------- Run the whole pipeline locally, before pushing ----------
build: ## Build the image
	docker build -t $(IMAGE) .

scan: ## Trivy scan, failing on HIGH/CRITICAL — the gate the CI job enforces
	trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 $(IMAGE)

sbom: ## Generate a CycloneDX SBOM
	syft $(IMAGE) -o cyclonedx-json=sbom.cdx.json
	@echo "components: $$(python3 -c "import json;print(len(json.load(open('sbom.cdx.json'))['components']))")"

sbom-inspect: sbom ## The number that surprises people
	@echo "--- direct dependencies you declared ---"
	@grep -vc '^#\|^$$' app/requirements.txt
	@echo "--- what actually ships in the image ---"
	@python3 -c "import json;c=json.load(open('sbom.cdx.json'))['components'];print(len(c),'components')"
	@echo
	@echo "That ratio is your real attack surface. It is the interview aside."

nonroot: build ## Prove the image does not run as root
	@echo -n "UID: "; docker run --rm --entrypoint id $(IMAGE) -u
	@docker run --rm --entrypoint id $(IMAGE) -u | grep -qv '^0$$' \
	  && echo "✓ non-root" || { echo "✗ RUNNING AS ROOT"; exit 1; }

## ---------- Exercise 2: watch it fail ----------
break-deps: ## Swap in known-vulnerable pins
	cp app/requirements.txt app/requirements.txt.bak
	cp app/requirements-vulnerable.txt app/requirements.txt
	@echo "now: make build scan   (expect a non-zero exit — that IS the lesson)"

fix-deps: ## Restore the clean pins
	mv app/requirements.txt.bak app/requirements.txt

## ---------- Signing (needs a registry you can push to) ----------
verify: ## Verify a published image's signature
	@test -n "$(REF)" || { echo "usage: make verify REF=ghcr.io/you/repo@sha256:..."; exit 1; }
	cosign verify \
	  --certificate-identity-regexp '^https://github.com/' \
	  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
	  $(REF)

rekor: ## Show the transparency-log entry for a signed image
	@test -n "$(REF)" || { echo "usage: make rekor REF=ghcr.io/you/repo@sha256:..."; exit 1; }
	cosign verify --certificate-identity-regexp '^https://github.com/' \
	  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
	  $(REF) 2>&1 | grep -i 'rekor\|tlog\|logIndex'

## ---------- OIDC setup (optional, needs an Azure subscription) ----------
oidc: ## Create the federated identity (free; the deploy target is not)
	cd terraform && terraform init && \
	  terraform apply -var github_org=$(ORG) -var github_repo=$(REPO) \
	                  -var resource_group_name=$(RG)

clean:
	rm -f sbom.cdx.json app/requirements.txt.bak

.PHONY: help tools build scan sbom sbom-inspect nonroot break-deps fix-deps \
        verify rekor oidc clean
