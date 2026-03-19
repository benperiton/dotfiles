#!/bin/bash
set -euo pipefail

echo "Removing pre-installed Docker packages that conflict with docker-ce..."

# These are the Fedora-bundled Docker packages that conflict with docker-ce
OLD_DOCKER_PACKAGES=(
    docker
    docker-client
    docker-client-latest
    docker-common
    docker-latest
    docker-latest-logrotate
    docker-logrotate
    docker-selinux
    docker-engine-selinux
    docker-engine
    moby-engine
    docker-cli
    docker-compose
    docker-buildx
)

INSTALLED=()
for pkg in "${OLD_DOCKER_PACKAGES[@]}"; do
    if rpm -q "$pkg" &>/dev/null; then
        INSTALLED+=("$pkg")
    fi
done

if [ ${#INSTALLED[@]} -gt 0 ]; then
    echo "Removing: ${INSTALLED[*]}"
    sudo dnf remove -y "${INSTALLED[@]}"
else
    echo "No conflicting Docker packages found"
fi
