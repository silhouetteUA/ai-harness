.PHONY: help deploy destroy cluster_deploy tofu_deploy check_prerequisites install_prerequisites

help:
	@echo "Makefile commands:"
	@echo "  help                  - Show this help message"
	@echo "  deploy                - Deploy the system"
	@echo "  destroy               - Destroy the system"
	@echo "  cluster_deploy        - Deploy Kind cluster"
	@echo "  tofu_deploy           - Deploy OpenTofu"
	@echo "  check_prerequisites   - Check prerequisites"
	@echo "  install_prerequisites - Install Kind and OpenTofu"

install_prerequisites: tofu_deploy cluster_deploy

CLUSTER_NAME := $(shell awk '/^name:/ {print $$2}' bootstrap/kind-config.yaml)
CLUSTER_NAME := $(if $(CLUSTER_NAME),$(CLUSTER_NAME),kind)

deploy: check_prerequisites
	@echo "[`date '+%H:%M:%S'`] Deployment started ..."
	@echo "Prerequisites met."
	@kind --version
	@tofu --version
	@echo "[`date '+%H:%M:%S'`] Creating kind cluster ..."
	@kind get clusters | grep -q "^$(CLUSTER_NAME)$$" || kind create cluster --config bootstrap/kind-config.yaml
	@echo "[`date '+%H:%M:%S'`] OpenTofu deployment started ..."
	@cd bootstrap && tofu init && tofu validate && tofu apply -auto-approve
	@echo "[`date '+%H:%M:%S'`] OpenTofu deployment finished ..."

destroy:
	@echo "[`date '+%H:%M:%S'`] Destroy started ..."
	@cd bootstrap && tofu destroy -auto-approve
	@echo "[`date '+%H:%M:%S'`] Deleting kind cluster ..."
	@kind delete cluster --name $(CLUSTER_NAME)
	@echo "[`date '+%H:%M:%S'`] Destroy finished ..."

cluster_deploy:
	@./scripts/createKind.sh

tofu_deploy:
	@./scripts/installOpenTofu.sh

check_prerequisites:
	@./scripts/checkPrerequisites.sh
