#!/bin/bash

if ! command -v tofu >/dev/null 2>&1; then
    echo "OpenTofu is not installed. Installing..."
    curl -fsSL https://get.opentofu.org/install-opentofu.sh | sh -s -- --install-method standalone
    echo "OpenTofu installation complete."
fi
