#!/bin/bash

if ! command -v kind >/dev/null 2>&1; then
    echo "kind is not installed. Installing..."
    ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    echo "Detected OS: $OS, ARCH: $ARCH"
    
    # Fetch latest version from GitHub API, fallback to v0.24.0 if it fails
    LATEST_KIND_VERSION=$(curl -s https://api.github.com/repos/kubernetes-sigs/kind/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$LATEST_KIND_VERSION" ]; then
        LATEST_KIND_VERSION="v0.24.0"
    fi
    
    echo "Installing kind version $LATEST_KIND_VERSION..."
    curl -fsSLo /tmp/kind "https://kind.sigs.k8s.io/dl/${LATEST_KIND_VERSION}/kind-${OS}-${ARCH}"
    sudo install -m 0755 /tmp/kind /usr/local/bin/kind
    rm -f /tmp/kind
    echo "kind installation complete."
fi
