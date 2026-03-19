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

# Verify we can access the vault
if ! op vault get ben-dotfiles &>/dev/null; then
    echo "ERROR: Cannot access ben-dotfiles vault. Check your 1Password account."
    exit 1
fi

# -- Chezmoi --
if ! command -v chezmoi &>/dev/null; then
    echo "==> Installing chezmoi..."
    sh -c "$(curl -fsSL https://get.chezmoi.io)"
fi

# -- Init and apply --
echo "==> Applying dotfiles..."
chezmoi init --apply benperiton

echo "==> Done! Log out and back in for all changes to take effect."
