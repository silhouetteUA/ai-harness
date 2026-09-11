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

deploy: check_prerequisites
	@echo "[`date '+%H:%M:%S'`] Deployment started ..."
	@echo "Prerequisites met."
	@kind --version
	@tofu --version
	@echo "[`date '+%H:%M:%S'`] OpenTofu deployment started ..."
	@cd bootstrap && tofu init && tofu validate && tofu apply -auto-approve
	@echo "[`date '+%H:%M:%S'`] OpenTofu deployment finished ..."

destroy:
	@echo "Destroying the OpenTofu infrastructure ..."
	@cd bootstrap && tofu destroy -auto-approve

cluster_deploy:
	@./scripts/createKind.sh

tofu_deploy:
	@./scripts/installOpenTofu.sh

check_prerequisites:
	@./scripts/checkPrerequisites.sh
