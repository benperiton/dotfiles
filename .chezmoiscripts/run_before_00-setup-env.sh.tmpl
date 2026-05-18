#!/bin/bash
set -euo pipefail

# Ensure common directories exist
mkdir -p ~/.config ~/.local/bin
mkdir -p ~/Coding/{projects,scripts,resources}
{{- if eq .machine_role "personal" }}
mkdir -p ~/Coding/projects/{ideas,personal}
{{- else if eq .machine_role "work" }}
mkdir -p ~/Coding/projects/{ideas,forks}
{{- end }}

# Set default shell to zsh
if [ "$SHELL" != "$(command -v zsh)" ] && command -v zsh &>/dev/null; then
    echo "Changing default shell to zsh"
    sudo chsh -s "$(command -v zsh)" "$USER"
fi
