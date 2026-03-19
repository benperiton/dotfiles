#!/bin/bash
set -euo pipefail

# Ensure common directories exist
mkdir -p ~/.config ~/.local/bin
mkdir -p ~/Coding/projects/{ideas,personal}
mkdir -p ~/Coding/{scripts,resources}

# Set default shell to zsh
if [ "$SHELL" != "$(command -v zsh)" ] && command -v zsh &>/dev/null; then
    echo "Changing default shell to zsh"
    sudo chsh -s "$(command -v zsh)" "$USER"
fi
