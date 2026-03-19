#!/bin/sh

LOCK_OPEN=$(printf '\xef\x82\x9c')    # U+F09C — fa-unlock
LOCK_SHUT=$(printf '\xef\x80\xa3')    # U+F023 — fa-lock

IP=$(curl -s --max-time 3 ifconfig.me)
IP="${IP:-unknown}"

# Check for active VPN (OpenVPN/IPSec) or WireGuard connections
VPN_NAME=$(nmcli -t -f NAME,TYPE,STATE con show --active | awk -F: '($2=="vpn" || $2=="wireguard") && $3=="activated" {print $1}')

if [ -z "$VPN_NAME" ]; then
    echo "{\"text\": \"$LOCK_OPEN LAN $IP\", \"class\": \"disconnected\", \"tooltip\": \"No VPN active\\nPublic IP: $IP\"}"
else
    echo "{\"text\": \"$LOCK_SHUT VPN $IP\", \"class\": \"connected\", \"tooltip\": \"$VPN_NAME\\nPublic IP: $IP\"}"
fi
