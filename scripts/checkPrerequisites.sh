#!/bin/bash

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "Checking prerequisites..."

missing_tools=()
installed_tools=()

# Check for kind
if command -v kind >/dev/null 2>&1; then
    installed_tools+=("kind")
else
    missing_tools+=("kind")
fi

# Check for OpenTofu (tofu)
if command -v tofu >/dev/null 2>&1; then
    installed_tools+=("tofu (OpenTofu)")
else
    missing_tools+=("tofu (OpenTofu)")
fi

# Output installed tools
if [ ${#installed_tools[@]} -gt 0 ]; then
    log "Installed tools:"
    for tool in "${installed_tools[@]}"; do
        log "  - $tool"
    done
fi

# Output missing tools
if [ ${#missing_tools[@]} -gt 0 ]; then
    log "Missing tools:"
    for tool in "${missing_tools[@]}"; do
        log "  - $tool"
    done
    echo ""
    log "Please run 'make install_prerequisites' to install them."
    exit 1
fi

log "All required tools are installed."
exit 0
