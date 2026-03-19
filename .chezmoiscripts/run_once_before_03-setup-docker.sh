#!/bin/bash
set -euo pipefail

echo "Configuring Docker..."

# Enable and start Docker
if ! systemctl is-enabled docker &>/dev/null; then
    sudo systemctl enable --now docker
fi

# Add current user to docker group
if ! groups "$USER" | grep -q docker; then
    echo "Adding $USER to docker group"
    sudo usermod -aG docker "$USER"
    echo "Log out and back in for group membership to take effect"
fi

echo "Docker configured"
