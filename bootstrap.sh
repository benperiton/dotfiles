#!/bin/bash
set -euo pipefail

# Bootstrap script for a fresh Fedora install
# Run: curl -fsSL <raw-url> | bash

echo "==> Installing base dependencies..."
sudo dnf install -y git openssh-server

# -- Enable SSH --
if ! systemctl is-enabled sshd &>/dev/null; then
    echo "==> Enabling sshd..."
    sudo systemctl enable --now sshd
fi

# -- 1Password CLI --
if ! command -v op &>/dev/null; then
    echo "==> Installing 1Password CLI..."
    sudo rpm --import https://downloads.1password.com/linux/keys/1password.asc
    sudo tee /etc/yum.repos.d/1password.repo >/dev/null <<'REPO'
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
REPO
    sudo dnf install -y 1password-cli
fi

echo "==> Signing in to 1Password..."
eval "$(op signin)"

# Verify we're signed in to 1Password (chezmoi pulls from the
# role-appropriate vault during init)
if ! op whoami &>/dev/null; then
    echo "ERROR: Not signed in to 1Password. Run 'op signin' and retry."
    exit 1
fi

# -- Chezmoi --
# Install from the Fedora repos so it lands on PATH (/usr/bin) and is
# kept current via `dnf upgrade`. The upstream get.chezmoi.io installer
# defaults its bindir to $(pwd)/bin, which on Fedora is NOT on PATH
# (only ~/.local/bin is), leaving chezmoi installed but unusable.
if ! command -v chezmoi &>/dev/null; then
    echo "==> Installing chezmoi..."
    sudo dnf install -y chezmoi
fi

# -- Init and apply --
echo "==> Applying dotfiles..."
chezmoi init --apply benperiton

echo "==> Done! Log out and back in for all changes to take effect."
