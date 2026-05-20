#!/bin/sh
# waybar custom/vpn status. Probes Cloudflare WARP first (work machines), then
# NetworkManager VPN/wireguard, then falls back to LAN-only. Emits a single
# JSON line with text/class/tooltip for waybar's return-type=json contract.
# Click handler lives in warp-toggle.sh.

LOCK_OPEN=$(printf '\xef\x82\x9c')    # U+F09C, fa-unlock
LOCK_SHUT=$(printf '\xef\x80\xa3')    # U+F023, fa-lock

# Public IP (best-effort; --max-time 3 prevents flapping links from stalling
# the bar). "unknown" on failure.
IP=$(curl -s --max-time 3 ifconfig.me)
# Strip anything that isn't a plausible IPv4/IPv6 character so a captive-portal
# HTML response can't break the JSON downstream. Empty result falls back to
# "unknown".
IP=$(printf '%s' "$IP" | tr -cd '0-9a-fA-F.:')
IP="${IP:-unknown}"

emit() {
    # $1 text, $2 class, $3 tooltip (use \n for newlines in tooltip)
    printf '{"text": "%s", "class": "%s", "tooltip": "%s"}\n' "$1" "$2" "$3"
}

# WARP branch
if command -v warp-cli >/dev/null 2>&1; then
    WARP_STATUS=$(warp-cli status 2>/dev/null)
    WARP_LINE1=$(printf '%s\n' "$WARP_STATUS" | head -n1)
    WARP_NET=$(printf '%s\n' "$WARP_STATUS" | sed -n 's/^Network: //p')

    case "$WARP_LINE1" in
        *Connected*)
            WARP_IP=$(ip -4 addr show dev CloudflareWARP 2>/dev/null \
                | awk '/inet / {split($2,a,"/"); print a[1]; exit}')
            if [ -z "$WARP_IP" ]; then
                # Daemon reports Connected but iface not up yet, treat as
                # transitional rather than lying to the user.
                emit "$LOCK_SHUT WARP Connecting" "connecting" "WARP: Connecting"
                exit 0
            fi
            # warp-cli settings prints "Include mode, with hosts/ips:" for
            # split tunnel (only listed routes go via WARP) and "Exclude mode"
            # for the reverse (everything except listed routes goes via WARP,
            # i.e. full tunnel). No literal "Split Tunnel mode" key exists.
            MODE=$(warp-cli settings 2>/dev/null | awk '
                /Include mode/ {print "split tunnel"; exit}
                /Exclude mode/ {print "full tunnel";  exit}')
            case "$MODE" in
                "split tunnel") EGRESS="egress via local ISP (split tunnel)" ;;
                "full tunnel")  EGRESS="egress via WARP" ;;
                *)              EGRESS="" ;;
            esac
            MODE_TAG=""
            [ -n "$MODE" ] && MODE_TAG=" ($MODE)"
            TOOLTIP="WARP: Connected${MODE_TAG}\\nWARP IP: ${WARP_IP}\\nPublic IP: ${IP}"
            [ -n "$EGRESS" ] && TOOLTIP="${TOOLTIP}  ${EGRESS}"
            [ -n "$WARP_NET" ] && TOOLTIP="${TOOLTIP}\\nNetwork: ${WARP_NET}"
            emit "$LOCK_SHUT WARP ${WARP_IP} / ${IP}" "connected" "$TOOLTIP"
            exit 0
            ;;
        *Connecting*)
            emit "$LOCK_SHUT WARP Connecting" "connecting" "WARP: Connecting"
            exit 0
            ;;
        *Disconnecting*)
            emit "$LOCK_SHUT WARP Disconnecting" "connecting" "WARP: Disconnecting"
            exit 0
            ;;
        *"Unable to Connect"*)
            emit "$LOCK_SHUT WARP Unreachable" "connecting" "WARP: Unable to Connect"
            exit 0
            ;;
    esac
    # Fall through (Disconnected, Disabled, unparseable, warp-cli error).
fi

# nmcli VPN/wireguard branch
VPN_NAME=$(nmcli -t -f NAME,TYPE,STATE con show --active \
    | awk -F: '($2=="vpn" || $2=="wireguard") && $3=="activated" {print $1}')

if [ -n "$VPN_NAME" ]; then
    WG_IFACE=$(nmcli -t -f GENERAL.IP-IFACE con show "$VPN_NAME" 2>/dev/null | cut -d: -f2)
    WG_IP=$(ip -4 addr show dev "$WG_IFACE" 2>/dev/null \
        | awk '/inet / {split($2,a,"/"); print a[1]}')
    emit "$LOCK_SHUT VPN (${VPN_NAME}) ${WG_IP:-unknown} / ${IP}" "connected" \
        "${VPN_NAME}\\nInternal IP: ${WG_IP:-unknown}\\nPublic IP: ${IP}"
    exit 0
fi

# LAN fallback
LAN_IP=$(ip -4 addr show up scope global 2>/dev/null \
    | awk '/inet / {split($2,a,"/"); print a[1]; exit}')
emit "$LOCK_OPEN LAN ${LAN_IP:-unknown} / ${IP}" "disconnected" \
    "No VPN active\\nInternal IP: ${LAN_IP:-unknown}\\nPublic IP: ${IP}"
