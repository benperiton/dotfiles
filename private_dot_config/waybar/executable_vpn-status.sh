#!/bin/sh

# Check for active VPN (OpenVPN/IPSec) or WireGuard connections
VPN_NAME=$(nmcli -t -f NAME,TYPE,STATE con show --active | awk -F: '($2=="vpn" || $2=="wireguard") && $3=="activated" {print $1}')

if [ -z "$VPN_NAME" ]; then
    echo '{"text": "󰿆 No VPN", "class": "disconnected", "tooltip": "No active VPN"}'
else
    IP=$(curl -s --max-time 3 ifconfig.me)
    echo "{\"text\": \"󰌾 $VPN_NAME\", \"class\": \"connected\", \"tooltip\": \"$VPN_NAME\\nIP: ${IP:-unknown}\"}"
fi
