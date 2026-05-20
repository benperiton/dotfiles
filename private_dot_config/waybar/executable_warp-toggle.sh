#!/bin/sh
# waybar custom/vpn on-click handler. Toggles Cloudflare WARP when present
# (work machines); on machines without WARP it falls back to opening the
# connection editor, so the module stays useful everywhere from a single
# config. After toggling, signal waybar (SIGRTMIN+8) so the module repaints
# immediately rather than waiting for its 5s tick.

if command -v warp-cli >/dev/null 2>&1; then
    if warp-cli status 2>/dev/null | grep -q 'Status update: Connected'; then
        warp-cli disconnect
    else
        warp-cli connect
    fi
    pkill -RTMIN+8 waybar 2>/dev/null || true
else
    nm-connection-editor
fi
