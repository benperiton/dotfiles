#!/bin/sh
# waybar custom/vpn on-click handler. Toggles Cloudflare WARP when present
# (work machines); on machines without WARP it falls back to the previous
# behaviour of opening the connection editor, so the module stays useful
# everywhere from a single config.

if command -v warp-cli >/dev/null 2>&1; then
    if warp-cli status 2>/dev/null | grep -q 'Status update: Connected'; then
        warp-cli disconnect
    else
        warp-cli connect
    fi
else
    nm-connection-editor
fi
