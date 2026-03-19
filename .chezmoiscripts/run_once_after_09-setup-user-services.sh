#!/bin/bash
set -euo pipefail

echo "Enabling user services..."

systemctl --user daemon-reload

for svc in ssh-agent.service tmux.service gammastep.service; do
    if ! systemctl --user is-enabled "$svc" &>/dev/null; then
        echo "Enabling $svc"
        systemctl --user enable --now "$svc"
    fi
done

echo "User services configured"
