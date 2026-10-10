.PHONY: help practice-init practice-plan practice-apply practice-destroy dev-init dev-plan dev-apply dev-destroy lint
.DEFAULT_GOAL := help

help:  ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS=":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

practice-init:     ## Init the FREE practice environment
	cd envs/practice && terraform init
practice-plan:     ## Plan practice (read the output properly)
	cd envs/practice && terraform plan
practice-apply:    ## Apply practice
	cd envs/practice && terraform apply
practice-destroy:  ## Destroy practice
	cd envs/practice && terraform destroy

dev-init:          ## Init dev (run bootstrap/bootstrap.sh first)
	cd envs/dev && terraform init
dev-plan:          ## 💰 Plan dev
	cd envs/dev && terraform plan -var-file=dev.tfvars
dev-apply:         ## 💰 Apply dev — COSTS MONEY
	cd envs/dev && terraform apply -var-file=dev.tfvars
dev-destroy:       ## 💰 DESTROY dev — run this when done
	cd envs/dev && terraform destroy -var-file=dev.tfvars

lint:              ## Format check + lint + security scan
	terraform fmt -check -recursive || (echo "run: terraform fmt -recursive" && exit 1)
	@command -v tflint >/dev/null && tflint --recursive || echo "(tflint not installed)"
	@command -v checkov >/dev/null && checkov -d . --quiet || echo "(checkov not installed)"
