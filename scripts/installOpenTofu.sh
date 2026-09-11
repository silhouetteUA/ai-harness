#!/bin/bash

log() { echo "[$(date '+%H:%M:%S')] $*"; }

if ! command -v tofu >/dev/null 2>&1; then
    log "OpenTofu is not installed. Starting to install OpenTofu..."
    curl -fsSL https://get.opentofu.org/install-opentofu.sh | sh -s -- --install-method standalone
    log "OpenTofu installation finished successfully."
else
    log "OpenTofu is already installed."
fi
