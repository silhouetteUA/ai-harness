.PHONY: help deploy cluster_deploy tofu_deploy check_prerequisites install_prerequisites

help:
	@echo "Makefile commands:"
	@echo "  help                  - Show this help message"
	@echo "  deploy                - Deploy the system"
	@echo "  cluster_deploy        - Deploy Kind cluster"
	@echo "  tofu_deploy           - Deploy OpenTofu"
	@echo "  check_prerequisites   - Check prerequisites"
	@echo "  install_prerequisites - Install Kind and OpenTofu"

install_prerequisites: tofu_deploy cluster_deploy

deploy: check_prerequisites install_prerequisites
	@echo "Prerequisites met."
	@kind --version
	@tofu --version
	@echo "Proceeding with the deployment ..."
	@echo "(Deploy logic not yet implemented)"

cluster_deploy:
	@./scripts/createKind.sh

tofu_deploy:
	@./scripts/installOpenTofu.sh

check_prerequisites:
	@./scripts/checkPrerequisites.sh
