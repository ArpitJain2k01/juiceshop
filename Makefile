# Secure Lab — one-command workflow
# Targets are filled in as each phase lands.

TF_DIR := terraform

.PHONY: help deploy verify destroy fmt validate

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*?## "}{printf "  %-10s %s\n", $$1, $$2}'

deploy: ## Bring up the full lab (apply + verifier gate)
	cd $(TF_DIR) && terraform init && terraform apply
	@echo ">> Deploy includes the verifier gate (added in Phase 5)."

verify: ## Re-run the log-delivery verifier with a fresh marker
	@echo "Verifier is added in Phase 5."

destroy: ## Tear down all lab resources
	cd $(TF_DIR) && terraform destroy

fmt: ## Format Terraform
	terraform -chdir=$(TF_DIR) fmt -recursive

validate: ## Validate Terraform (no backend)
	terraform -chdir=$(TF_DIR) init -backend=false && terraform -chdir=$(TF_DIR) validate
