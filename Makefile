# Secure Lab — one-command workflow

TF_DIR  := terraform
VENV    := verifier/.venv
PYTHON  := $(VENV)/bin/python

.PHONY: help deploy verify destroy fmt validate venv

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*?## "}{printf "  %-10s %s\n", $$1, $$2}'

deploy: ## Bring up the full lab, then gate on the verifier (fails if log delivery fails)
	cd $(TF_DIR) && terraform init && terraform apply -auto-approve
	$(MAKE) verify

verify: venv ## Run the log-delivery verifier with a fresh marker (needs the WireGuard VPN up)
	@WAF_IP=$$(cd $(TF_DIR) && terraform output -raw app_private_ip); \
	 WZ_IP=$$(cd $(TF_DIR) && terraform output -raw wazuh_private_ip); \
	 WAF_URL=http://$$WAF_IP:30443 \
	 INDEXER_URL=https://$$WZ_IP:9200 \
	 INDEXER_USER=$${INDEXER_USER:-admin} \
	 INDEXER_PASSWORD=$${INDEXER_PASSWORD:?set INDEXER_PASSWORD in your environment} \
	 $(PYTHON) verifier/verify.py

venv: ## Create the verifier virtualenv and install deps
	@test -d $(VENV) || python3 -m venv $(VENV)
	@$(VENV)/bin/pip -q install -r verifier/requirements.txt

destroy: ## Tear down all lab resources
	cd $(TF_DIR) && terraform destroy -auto-approve

fmt: ## Format Terraform
	terraform -chdir=$(TF_DIR) fmt -recursive

validate: ## Validate Terraform (no backend)
	terraform -chdir=$(TF_DIR) init -backend=false && terraform -chdir=$(TF_DIR) validate
