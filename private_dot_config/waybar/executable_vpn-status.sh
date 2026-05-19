#!/bin/sh

LOCK_OPEN=$(printf '\xef\x82\x9c')    # U+F09C — fa-unlock
LOCK_SHUT=$(printf '\xef\x80\xa3')    # U+F023 — fa-lock

IP=$(curl -s --max-time 3 ifconfig.me)
IP="${IP:-unknown}"

# Cloudflare WARP (work machines) is the warp-svc daemon, not an nmcli
# connection, so check it via warp-cli before the generic logic. Absent on
# machines without the package -> fall through to the nmcli check below.
if command -v warp-cli >/dev/null 2>&1; then
    WARP=$(warp-cli status 2>/dev/null | awk -F': ' '/Status update/ {print $2; exit}')
    case "$WARP" in
        Connected)
            WARP_IP=$(ip -4 addr show dev CloudflareWARP 2>/dev/null | awk '/inet / {split($2,a,"/"); print a[1]; exit}')
            echo "{\"text\": \"$LOCK_SHUT WARP ${WARP_IP:-on} / $IP\", \"class\": \"connected\", \"tooltip\": \"Cloudflare WARP: Connected\\nWARP IP: ${WARP_IP:-unknown}\\nPublic IP: $IP\"}"
            exit 0
            ;;
        Connecting*|Disconnecting*)
            echo "{\"text\": \"$LOCK_OPEN WARP $WARP\", \"class\": \"connecting\", \"tooltip\": \"Cloudflare WARP: $WARP\"}"
            exit 0
            ;;
        Disconnected|"")
            : # not connected via WARP; fall through to nmcli / LAN display
            ;;
        *)
            echo "{\"text\": \"$LOCK_OPEN WARP $WARP\", \"class\": \"disconnected\", \"tooltip\": \"Cloudflare WARP: $WARP\"}"
            exit 0
            ;;
    esac
fi

# Check for active VPN (OpenVPN/IPSec) or WireGuard connections
VPN_NAME=$(nmcli -t -f NAME,TYPE,STATE con show --active | awk -F: '($2=="vpn" || $2=="wireguard") && $3=="activated" {print $1}')

if [ -z "$VPN_NAME" ]; then
    LAN_IP=$(ip -4 addr show up scope global 2>/dev/null | awk '/inet / {split($2,a,"/"); print a[1]; exit}')
    echo "{\"text\": \"$LOCK_OPEN LAN ${LAN_IP:-unknown} / $IP\", \"class\": \"disconnected\", \"tooltip\": \"No VPN active\\nInternal IP: ${LAN_IP:-unknown}\\nPublic IP: $IP\"}"
else
    WG_IFACE=$(nmcli -t -f GENERAL.IP-IFACE con show "$VPN_NAME" 2>/dev/null | cut -d: -f2)
    WG_IP=$(ip -4 addr show dev "$WG_IFACE" 2>/dev/null | awk '/inet / {split($2,a,"/"); print a[1]}')
    echo "{\"text\": \"$LOCK_SHUT VPN ($VPN_NAME) ${WG_IP:-unknown} / $IP\", \"class\": \"connected\", \"tooltip\": \"$VPN_NAME\\nInternal IP: ${WG_IP:-unknown}\\nPublic IP: $IP\"}"
fi
