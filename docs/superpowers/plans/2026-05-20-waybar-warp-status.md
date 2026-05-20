# Waybar Cloudflare WARP status + toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the existing waybar `custom/vpn` module aware of Cloudflare WARP so the bottom bar shows whether WARP is connected, transitions visibly while toggling, and clicks repaint immediately.

**Architecture:** Extend the existing `vpn-status.sh` JSON-producing shell script with a WARP probe in front of the current nmcli probe. WARP wins when present and on; nmcli VPN/wireguard rendering is preserved when WARP is absent or off. The existing `warp-toggle.sh` on-click handler is kept and gains a one-line SIGRTMIN+8 nudge so waybar repaints immediately instead of waiting up to 5s for the next poll. CSS gains a `.connecting` orange class. Module gets `"signal": 8`.

**Tech Stack:** POSIX shell, `warp-cli`, `nmcli`, `ip`, `curl`, waybar 0.14, GTK CSS, chezmoi (dotfiles management).

**Spec:** `docs/superpowers/specs/2026-05-20-waybar-warp-status-design.md`

**Important environment notes:**
- All source edits go to `~/.local/share/chezmoi/private_dot_config/waybar/`, NOT to live `~/.config/waybar/` (the chezmoi/dotfiles workflow).
- `chezmoi apply` requires 1Password and is avoided. For local testing we copy files manually from the chezmoi source to `~/.config/waybar/` and reload waybar.
- The user's shell aliases `grep` to `rg`. Use `rg` in any verification commands.
- This is a shell + config change with no automated test framework. Verification is manual against the four WARP states. There is no `pytest` or similar to run; the "expected output" of each verification step is described in prose.

---

## File Map

| Path (relative to `~/.local/share/chezmoi/`) | Action | Responsibility |
|---|---|---|
| `private_dot_config/waybar/executable_vpn-status.sh` | Rewrite | Emit the JSON status line. Probes WARP first, then nmcli VPN, then LAN. |
| `private_dot_config/waybar/executable_warp-toggle.sh` | Modify | After connect/disconnect, signal waybar to repaint immediately. |
| `private_dot_config/waybar/config.jsonc` | Modify | Add `"signal": 8` to the `custom/vpn` module so it reacts to SIGRTMIN+8. |
| `private_dot_config/waybar/style.css` | Modify | Add `#custom-vpn.connecting` orange rule. |
| `docs/superpowers/plans/2026-05-20-waybar-warp-status.md` | Create | This plan. |

The script file is doing one thing (produce a JSON line for one module). Keeping it as one file rather than splitting into per-state helpers stays under 60 lines and matches the existing single-file pattern for waybar custom modules in this repo.

---

## Task 1: Rewrite `vpn-status.sh` with WARP detection

**Files:**
- Modify: `~/.local/share/chezmoi/private_dot_config/waybar/executable_vpn-status.sh`

The script's current contract is a single line of JSON with `text`, `class`, `tooltip` keys to stdout. We preserve that contract. We add a WARP branch in front of the existing nmcli branch and add a transitional class for the "Connecting/Disconnecting/Unable to Connect" states.

- [ ] **Step 1: Read the current script to confirm starting point**

Run:
```bash
cat ~/.local/share/chezmoi/private_dot_config/waybar/executable_vpn-status.sh
```

Expected: 20-line script with `LOCK_OPEN`/`LOCK_SHUT` constants, a curl to ifconfig.me, an nmcli VPN/wireguard probe, and a two-branch JSON output. No WARP awareness.

- [ ] **Step 2: Replace the script with the WARP-aware version**

Write the file content as:

```sh
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
IP="${IP:-unknown}"

emit() {
    # $1 text, $2 class, $3 tooltip (use \n for newlines in tooltip)
    printf '{"text": "%s", "class": "%s", "tooltip": "%s"}\n' "$1" "$2" "$3"
}

# ── WARP branch ────────────────────────────────────────────
if command -v warp-cli >/dev/null 2>&1; then
    WARP_STATUS=$(warp-cli status 2>/dev/null)
    WARP_LINE1=$(printf '%s\n' "$WARP_STATUS" | head -n1)
    WARP_NET=$(printf '%s\n' "$WARP_STATUS" | sed -n '2p' | sed 's/^Network: //')

    case "$WARP_LINE1" in
        *Connected*)
            WARP_IP=$(ip -4 addr show dev CloudflareWARP 2>/dev/null \
                | awk '/inet / {split($2,a,"/"); print a[1]; exit}')
            if [ -z "$WARP_IP" ]; then
                # Daemon reports Connected but iface not up yet, treat as
                # transitional rather than lying to the user.
                emit "$LOCK_SHUT WARP Connecting…" "connecting" "WARP: Connecting"
                exit 0
            fi
            MODE_LINE=$(warp-cli settings 2>/dev/null \
                | awk -F': ' '/Split Tunnel mode/ {print $2; exit}')
            case "$MODE_LINE" in
                *include*) MODE="split tunnel"; EGRESS="egress via local ISP (split tunnel)" ;;
                *exclude*) MODE="full tunnel";  EGRESS="egress via WARP" ;;
                *)         MODE="";             EGRESS="" ;;
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
            emit "$LOCK_SHUT WARP Connecting…" "connecting" "WARP: Connecting"
            exit 0
            ;;
        *Disconnecting*)
            emit "$LOCK_SHUT WARP Disconnecting…" "connecting" "WARP: Disconnecting"
            exit 0
            ;;
        *"Unable to Connect"*)
            emit "$LOCK_SHUT WARP Unreachable" "connecting" "WARP: Unable to Connect"
            exit 0
            ;;
    esac
    # Fall through (Disconnected, Disabled, unparseable, warp-cli error).
fi

# ── nmcli VPN/wireguard branch ─────────────────────────────
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

# ── LAN fallback ───────────────────────────────────────────
LAN_IP=$(ip -4 addr show up scope global 2>/dev/null \
    | awk '/inet / {split($2,a,"/"); print a[1]; exit}')
emit "$LOCK_OPEN LAN ${LAN_IP:-unknown} / ${IP}" "disconnected" \
    "No VPN active\\nInternal IP: ${LAN_IP:-unknown}\\nPublic IP: ${IP}"
```

Notes for the implementer:
- The file is in chezmoi's `executable_` form; chezmoi sets the executable bit on apply. Preserve the existing mode (already 755) when writing through the Write tool.
- POSIX `sh`, not bash. No `[[ ]]`, no `==` in test, no arrays.
- Tooltip uses `\\n` so the printf format keeps the backslash through to waybar, which parses it as a real newline.
- `case` substring patterns avoid regex/grep entirely and tolerate minor WARP version wording shifts.

- [ ] **Step 3: Sanity check the script parses and runs**

Run:
```bash
sh -n ~/.local/share/chezmoi/private_dot_config/waybar/executable_vpn-status.sh && echo "syntax OK"
~/.local/share/chezmoi/private_dot_config/waybar/executable_vpn-status.sh
```

Expected: `syntax OK` on the first line. The second line emits one JSON object. With WARP currently connected on this machine, expect text starting with `WARP 100.96.` and `"class": "connected"`. If WARP is disconnected at test time, expect a `LAN ... / public` line with `"class": "disconnected"`.

- [ ] **Step 4: Verify JSON validity**

Run:
```bash
~/.local/share/chezmoi/private_dot_config/waybar/executable_vpn-status.sh | python3 -m json.tool
```

Expected: pretty-printed JSON with no parse error. Newlines in tooltip should appear as `\n` escapes in the JSON, not literal newlines (the Python json.tool will preserve them as escapes).

- [ ] **Step 5: Commit**

```bash
cd ~/.local/share/chezmoi
git add private_dot_config/waybar/executable_vpn-status.sh
git commit -m "waybar: add Cloudflare WARP detection to vpn-status"
```

---

## Task 2: Add immediate-repaint signal to `warp-toggle.sh`

**Files:**
- Modify: `~/.local/share/chezmoi/private_dot_config/waybar/executable_warp-toggle.sh`

After warp-cli connect/disconnect, send SIGRTMIN+8 to waybar so the `custom/vpn` module re-runs immediately and the user sees the orange transitional state without waiting up to 5s.

- [ ] **Step 1: Read the current script**

Run:
```bash
cat ~/.local/share/chezmoi/private_dot_config/waybar/executable_warp-toggle.sh
```

Expected: the existing 16-line if/else that toggles WARP when warp-cli exists and falls back to nm-connection-editor otherwise.

- [ ] **Step 2: Replace with the version that signals waybar after toggling**

Write the file content as:

```sh
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
```

Notes:
- `pkill -RTMIN+8` is the POSIX way to send the real-time signal that waybar maps to module signal slot 8 (configured in Task 3). The `|| true` keeps a missing waybar process from making the click error-exit, which would surface in waybar's stderr log.
- The existing `grep -q 'Status update: Connected'` is retained even though Task 1's status script uses `case`. They're independent code paths and the toggle script doesn't need the broader state matrix.

- [ ] **Step 3: Sanity check syntax**

Run:
```bash
sh -n ~/.local/share/chezmoi/private_dot_config/waybar/executable_warp-toggle.sh && echo "syntax OK"
```

Expected: `syntax OK`.

- [ ] **Step 4: Commit**

```bash
cd ~/.local/share/chezmoi
git add private_dot_config/waybar/executable_warp-toggle.sh
git commit -m "waybar: signal repaint after WARP toggle"
```

---

## Task 3: Wire `"signal": 8` into the `custom/vpn` module

**Files:**
- Modify: `~/.local/share/chezmoi/private_dot_config/waybar/config.jsonc`

Waybar's `signal` key on a custom module is the RT-signal slot it listens on. Slot 8 corresponds to `pkill -RTMIN+8`.

- [ ] **Step 1: Locate the `custom/vpn` block**

Run:
```bash
rg -n '"custom/vpn"' ~/.local/share/chezmoi/private_dot_config/waybar/config.jsonc
```

Expected: one match, currently around line 122.

- [ ] **Step 2: Add the `signal` key**

Replace the block:

```jsonc
        "custom/vpn": {
            "format": "{}",
            "return-type": "json",
            "exec": "~/.config/waybar/vpn-status.sh",
            "interval": 5,
            "on-click": "~/.config/waybar/warp-toggle.sh"
        },
```

with:

```jsonc
        "custom/vpn": {
            "format": "{}",
            "return-type": "json",
            "exec": "~/.config/waybar/vpn-status.sh",
            "interval": 5,
            "signal": 8,
            "on-click": "~/.config/waybar/warp-toggle.sh"
        },
```

- [ ] **Step 3: Verify the file is still valid JSONC (jq tolerates // comments via `--`. Use python for a stricter check that allows the `// -*- mode: jsonc -*-` line.)**

Run:
```bash
python3 -c "import re, json; s=open('$HOME/.local/share/chezmoi/private_dot_config/waybar/config.jsonc').read(); s=re.sub(r'(^|\s)//[^\n]*','', s, flags=re.M); json.loads(s); print('jsonc OK')"
```

Expected: `jsonc OK`. If you see a `JSONDecodeError`, the edit broke the structure; check for stray commas.

- [ ] **Step 4: Commit**

```bash
cd ~/.local/share/chezmoi
git add private_dot_config/waybar/config.jsonc
git commit -m "waybar: listen for SIGRTMIN+8 on custom/vpn"
```

---

## Task 4: Add `.connecting` CSS class

**Files:**
- Modify: `~/.local/share/chezmoi/private_dot_config/waybar/style.css`

The status script emits `"class": "connecting"` for transitional states. Today only `.connected` (#fabd2f yellow) and `.disconnected` (#a89984 grey) are styled.

- [ ] **Step 1: Locate the VPN CSS block**

Run:
```bash
rg -n '#custom-vpn' ~/.local/share/chezmoi/private_dot_config/waybar/style.css
```

Expected: three lines, the base rule plus `.disconnected` and `.connected` variants.

- [ ] **Step 2: Add `.connecting` after `.connected`**

Replace:

```css
#custom-vpn.connected {
    color: #fabd2f;
}
```

with:

```css
#custom-vpn.connected {
    color: #fabd2f;
}

#custom-vpn.connecting {
    color: #fe8019;   /* gruvbox orange, matches existing mode highlight */
}
```

- [ ] **Step 3: Commit**

```bash
cd ~/.local/share/chezmoi
git add private_dot_config/waybar/style.css
git commit -m "waybar: orange connecting state for custom/vpn"
```

---

## Task 5: Local deploy and end-to-end verification

**Files:** none modified; manual verification only.

We're not running `chezmoi apply` (1Password dependency). Instead, copy the four touched files from chezmoi source to live `~/.config/waybar/` and reload waybar, then walk the WARP state matrix.

- [ ] **Step 1: Copy updated files to live location**

Run:
```bash
SRC=~/.local/share/chezmoi/private_dot_config/waybar
DST=~/.config/waybar
command cp -f "$SRC/executable_vpn-status.sh" "$DST/vpn-status.sh"
command cp -f "$SRC/executable_warp-toggle.sh" "$DST/warp-toggle.sh"
command cp -f "$SRC/config.jsonc"              "$DST/config.jsonc"
command cp -f "$SRC/style.css"                 "$DST/style.css"
chmod +x "$DST/vpn-status.sh" "$DST/warp-toggle.sh"
```

Note: `command cp -f` bypasses the interactive `cp -i` alias the user's shell uses; without it the non-interactive Bash tool's `cp` silently aborts on the overwrite prompt (per the user's shell-interactive-alias gotcha memory).

- [ ] **Step 2: Reload waybar**

Run:
```bash
pkill -SIGUSR2 waybar
```

Expected: waybar reloads in place without dropping the bar. If the bar disappears entirely, the config.jsonc edit broke something. Re-run the Task 3 syntax check and inspect `journalctl --user -u waybar -n 50`, or restart waybar with `swaymsg exec waybar` from a Sway-aware terminal.

- [ ] **Step 3: Verify "WARP connected" rendering**

Ensure WARP is on:
```bash
warp-cli connect
sleep 2
warp-cli status
```

Expected `warp-cli status`: `Status update: Connected`.

Check the bar visually: bottom-left should now show a yellow lock icon followed by `WARP 100.96.x.x / <public IP>`. Hover for the tooltip and confirm it includes `WARP: Connected (split tunnel)`, `WARP IP: 100.96.x.x`, `Public IP:` with the `egress via local ISP (split tunnel)` hint, and a `Network: healthy` line.

If the tooltip is missing the `(split tunnel)` tag, run `warp-cli settings | grep -i 'split tunnel'` and verify the mode line exists. If it doesn't, the omission is correct per spec ("we don't guess").

- [ ] **Step 4: Verify transitional + disconnected states via a click**

Click the bar module. Expected sequence:
1. Within ~100ms the label changes to orange "WARP Disconnecting…".
2. Within 1-3 seconds (warp-svc shutdown time) it settles on grey "LAN <lan IP> / <public IP>" with the unlock icon.

If the orange state is too fast to see, repeat with `warp-cli disconnect; sleep 0.1; warp-cli status` to confirm the script renders `Disconnecting` text directly.

Click again. Expected:
1. Within ~100ms: orange "WARP Connecting…".
2. Within ~2 seconds: yellow `WARP 100.96.x.x / <public IP>`.

- [ ] **Step 5: Verify the no-warp-cli fall-through**

Run:
```bash
PATH=/usr/bin:/bin env -i HOME=$HOME PATH=/tmp ~/.config/waybar/vpn-status.sh
```

Expected: the script runs without `warp-cli` on `PATH` and emits either the nmcli-VPN JSON (if a corp VPN happens to be active) or the LAN-fallback JSON. The `class` should be `connected` or `disconnected`, never `connecting`. No error output. This proves the WARP branch fails closed.

- [ ] **Step 6: Verify the "Unable to Connect" path (optional, only if a test window is convenient)**

Block WARP control plane briefly:
```bash
sudo nft add rule inet filter output ip daddr 162.159.193.10 drop  # cloudflare WARP control plane
warp-cli disconnect; sleep 1; warp-cli connect
```

Watch the bar for orange "WARP Unreachable". Then clean up:
```bash
sudo nft flush ruleset  # ONLY if you have no other nft rules; otherwise delete the specific rule.
warp-cli connect
```

If you don't want to touch nft on a work machine, skip this step. The text path is exercised by the case branch in Task 1 and the script handles it whether or not you see it live.

- [ ] **Step 7: Push the dotfiles**

```bash
cd ~/.local/share/chezmoi
ssh-add ~/.ssh/id_github  # passphrase prompt, once per session per the user's workflow
git push origin main
```

Expected: push succeeds. If `ssh-add` is unavailable in this non-interactive harness, surface the push command to the user to run themselves with `! git -C ~/.local/share/chezmoi push origin main`.

---

## Self-review notes

- Spec coverage:
  - WARP detection ahead of nmcli: Task 1, case branches.
  - Three states (connected / transitional / disconnected): Task 1 `case`, Task 4 CSS.
  - Label `WARP <warp IP> / <public IP>`: Task 1 `emit` call in the `Connected` branch.
  - Tooltip with split/full tunnel tag and `Network:` line: Task 1.
  - Falls back to nmcli on non-WARP machines: Task 1 falls through if `warp-cli` is missing OR status doesn't match the WARP branches.
  - Immediate repaint via signal: Tasks 2 + 3.
  - CSS connecting orange: Task 4.
  - Files-touched list matches spec: yes (4 files).
  - Manual test coverage of the four states: Task 5 steps 3-6.
- No placeholders or "implement later" stubs; every step has its full code or command.
- Type consistency: the `emit` shell function signature `emit text class tooltip` is used identically in every branch of Task 1's script.
