# Waybar VPN role-split + WARP pinned install Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the waybar VPN module's behaviour selected by `machine_role` (WARP on work, WireGuard on personal) instead of a runtime probe, and switch the WARP install to a pinned, cleanly-resolved rpm with no `--nodeps`.

**Architecture:** Two waybar scripts become chezmoi `.tmpl`s that render only their role's branch with a shared LAN fallback; the toggle script is renamed `warp-toggle.sh` -> `vpn-toggle.sh` and `config.jsonc`'s `on-click` is repointed. The WARP install block in script 01 pins version `2026.3.846.0`, verifies a baked-in SHA256 (the artifact is unsigned), drops the yum repo, and installs via `dnf` with normal dependency resolution.

**Tech Stack:** chezmoi (Go text/template), POSIX sh, bash, dnf, Cloudflare WARP, NetworkManager/WireGuard.

**Validation model:** This repo has no build/test; validation is `chezmoi execute-template` rendering + `sh -n`/`bash -n` syntax checks (per `CLAUDE.md`). To force a branch, `sed` substitutes a literal for `.machine_role` before rendering. No `chezmoi apply` here (it needs 1Password); deployment is the user's call later.

**Working directory for all tasks:** `~/.local/share/chezmoi`

---

### Task 1: Role-split `vpn-status.sh`

**Files:**
- Create: `private_dot_config/waybar/executable_vpn-status.sh.tmpl`
- Delete: `private_dot_config/waybar/executable_vpn-status.sh`

- [ ] **Step 1: Write the new templated script**

Create `private_dot_config/waybar/executable_vpn-status.sh.tmpl` with exactly:

```sh
#!/bin/sh
# waybar custom/vpn status. Rendered per machine_role (chezmoi template): WARP on
# work, NetworkManager VPN/WireGuard on personal; both fall back to a LAN-only
# readout. Emits a single JSON line with text/class/tooltip for waybar's
# return-type=json contract. Click handler lives in vpn-toggle.sh.

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

{{ if eq .machine_role "work" -}}
# WARP branch (work). warp-cli is installed by script 01 (work-gated); the guard
# keeps the bar on the LAN readout if WARP is somehow absent.
if command -v warp-cli >/dev/null 2>&1; then
    WARP_STATUS=$(warp-cli status 2>/dev/null)
    WARP_LINE1=$(printf '%s\n' "$WARP_STATUS" | head -n1)
    WARP_NET=$(printf '%s\n' "$WARP_STATUS" | sed -n 's/^Network: //p')

    case "$WARP_LINE1" in
        *Connected*)
            WARP_IP=$(ip -4 addr show dev CloudflareWARP 2>/dev/null \
                | awk '/inet / {split($2,a,"/"); print a[1]; exit}')
            if [ -z "$WARP_IP" ]; then
                # Daemon reports Connected but iface not up yet; treat as
                # transitional rather than lying to the user.
                emit "$LOCK_SHUT WARP Connecting" "connecting" "WARP: Connecting"
                exit 0
            fi
            # warp-cli settings prints "Include mode" for split tunnel and
            # "Exclude mode" for full tunnel; there is no literal "Split Tunnel"
            # key.
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
{{- else -}}
# nmcli VPN/WireGuard branch (personal). Shows the active NetworkManager VPN or
# WireGuard profile; the standard WireGuard profiles are imported by script 07.
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
{{- end }}

# LAN fallback (shared)
LAN_IP=$(ip -4 addr show up scope global 2>/dev/null \
    | awk '/inet / {split($2,a,"/"); print a[1]; exit}')
emit "$LOCK_OPEN LAN ${LAN_IP:-unknown} / ${IP}" "disconnected" \
    "No VPN active\\nInternal IP: ${LAN_IP:-unknown}\\nPublic IP: ${IP}"
```

- [ ] **Step 2: Remove the old non-template script**

```bash
git rm private_dot_config/waybar/executable_vpn-status.sh
```

- [ ] **Step 3: Verify the work branch renders to valid sh**

```bash
sed 's/\.machine_role/"work"/g' private_dot_config/waybar/executable_vpn-status.sh.tmpl \
  | chezmoi execute-template | sh -n && echo "OK work"
```
Expected: prints `OK work`, no syntax errors.

- [ ] **Step 4: Verify the personal branch renders to valid sh**

```bash
sed 's/\.machine_role/"personal"/g' private_dot_config/waybar/executable_vpn-status.sh.tmpl \
  | chezmoi execute-template | sh -n && echo "OK personal"
```
Expected: prints `OK personal`, no syntax errors.

- [ ] **Step 5: Eyeball that each branch contains only its own logic**

```bash
sed 's/\.machine_role/"work"/g' private_dot_config/waybar/executable_vpn-status.sh.tmpl \
  | chezmoi execute-template | grep -c 'warp-cli'      # expect >0
sed 's/\.machine_role/"personal"/g' private_dot_config/waybar/executable_vpn-status.sh.tmpl \
  | chezmoi execute-template | grep -c 'warp-cli'      # expect 0
sed 's/\.machine_role/"personal"/g' private_dot_config/waybar/executable_vpn-status.sh.tmpl \
  | chezmoi execute-template | grep -c 'nmcli'         # expect >0
```
Expected: `>0`, `0`, `>0` respectively. Both rendered outputs must end with the shared `# LAN fallback` block.

- [ ] **Step 6: Commit**

```bash
git add private_dot_config/waybar/executable_vpn-status.sh.tmpl
git commit -m "waybar: render vpn-status.sh per machine_role (WARP work / WireGuard personal)"
```

---

### Task 2: Rename + role-split the toggle, repoint `config.jsonc`

**Files:**
- Create: `private_dot_config/waybar/executable_vpn-toggle.sh.tmpl`
- Delete: `private_dot_config/waybar/executable_warp-toggle.sh`
- Modify: `private_dot_config/waybar/config.jsonc:128`

- [ ] **Step 1: Write the new templated toggle**

Create `private_dot_config/waybar/executable_vpn-toggle.sh.tmpl` with exactly:

```sh
#!/bin/sh
# waybar custom/vpn on-click handler. Rendered per machine_role (chezmoi
# template): toggles Cloudflare WARP on work; opens the NetworkManager
# connection editor on personal (where the standard WireGuard profiles from
# script 07 live). After a work toggle, signal waybar (SIGRTMIN+8) so custom/vpn
# repaints immediately rather than waiting for its 5s tick.

{{ if eq .machine_role "work" -}}
if warp-cli status 2>/dev/null | grep -q 'Status update: Connected'; then
    warp-cli disconnect
else
    warp-cli connect
fi
pkill -RTMIN+8 waybar 2>/dev/null || true
{{- else -}}
nm-connection-editor
{{- end }}
```

- [ ] **Step 2: Remove the old toggle script**

```bash
git rm private_dot_config/waybar/executable_warp-toggle.sh
```

- [ ] **Step 3: Repoint the module's on-click in `config.jsonc`**

Change line 128 from:
```
            "on-click": "~/.config/waybar/warp-toggle.sh"
```
to:
```
            "on-click": "~/.config/waybar/vpn-toggle.sh"
```
(The `exec` on line 125 stays `~/.config/waybar/vpn-status.sh` - the deployed target name is unchanged by templating.)

- [ ] **Step 4: Verify both branches render to valid sh**

```bash
sed 's/\.machine_role/"work"/g' private_dot_config/waybar/executable_vpn-toggle.sh.tmpl \
  | chezmoi execute-template | sh -n && echo "OK work"
sed 's/\.machine_role/"personal"/g' private_dot_config/waybar/executable_vpn-toggle.sh.tmpl \
  | chezmoi execute-template | sh -n && echo "OK personal"
```
Expected: `OK work` and `OK personal`.

- [ ] **Step 5: Verify branch contents and the config edit**

```bash
sed 's/\.machine_role/"work"/g' private_dot_config/waybar/executable_vpn-toggle.sh.tmpl \
  | chezmoi execute-template | grep -c 'warp-cli'              # expect >0
sed 's/\.machine_role/"personal"/g' private_dot_config/waybar/executable_vpn-toggle.sh.tmpl \
  | chezmoi execute-template | grep -c 'nm-connection-editor' # expect >0
rg -n 'warp-toggle' private_dot_config/waybar/config.jsonc    # expect no matches
rg -n 'vpn-toggle'  private_dot_config/waybar/config.jsonc    # expect line 128
```
Expected: `>0`, `>0`, no `warp-toggle` match, one `vpn-toggle` match.

- [ ] **Step 6: Commit**

```bash
git add private_dot_config/waybar/executable_vpn-toggle.sh.tmpl private_dot_config/waybar/config.jsonc
git commit -m "waybar: split vpn toggle per role; rename warp-toggle.sh -> vpn-toggle.sh"
```

---

### Task 3: Pinned clean WARP install in script 01

**Files:**
- Modify: `.chezmoiscripts/run_onchange_before_01-install-packages.sh.tmpl:186-222`

- [ ] **Step 1: Replace the WARP block**

Replace the entire block from line 186 (`{{- if eq .machine_role "work" }}`) through line 222 (`{{- end }}`) with exactly:

```
{{- if eq .machine_role "work" }}

# Cloudflare WARP (Zero Trust client). Fedora is community-supported, not
# officially supported by Cloudflare. The latest rpm hard-Requires webkit2gtk3,
# which Fedora 43 removed (it ships webkit2gtk4.1 / webkitgtk6.0), so installing
# the latest is unsatisfiable. We instead pin a vetted older build whose Requires
# are only ca-certificates, dbus, desktop-file-utils, glibc, iproute, libpcap,
# nftables and nss-tools -- all in Fedora's stock repos -- so it installs cleanly
# with normal dependency resolution (no --nodeps).
#
# The pinned artifact is fetched directly from downloads.cloudflareclient.com and
# is NOT GPG-signed (rpm -Kv shows digests only; all signature headers are none),
# so we verify it against a pinned SHA256 instead of a signature. No signed copy
# of this clean version exists (the signed repo serves only the broken latest),
# so this is the integrity ceiling. We deliberately do NOT add the cloudflare-warp
# yum repo: an enabled repo would make `dnf upgrade` try (and fail) to pull the
# webkit2gtk3-requiring latest. To bump WARP, change WARP_PIN + WARP_SHA256 below;
# this is a run_onchange script so editing them re-runs this block.
#
# Enrollment stays manual via SSO (warp-cli teams-enroll <team>; warp-cli
# connect), intentionally not scripted, so no org name or secret lives in the
# repo. The GUI tray (warp-desktop-svc user unit) is masked in script 09; WARP
# status lives in waybar (custom/vpn) instead.
WARP_PIN="2026.3.846.0"
WARP_SHA256="a272001189ffdfe6886b5520d396d17c99065fb66f9aaf3a48e36ca6e0fa6358"
WARP_URL="https://downloads.cloudflareclient.com/v1/download/fedora34-intel/version/${WARP_PIN}"

# Remove the repo left by the previous --nodeps approach so dnf upgrade can't try
# the broken latest. No-op once gone.
if [ -f /etc/yum.repos.d/cloudflare-warp.repo ]; then
    sudo rm -f /etc/yum.repos.d/cloudflare-warp.repo
fi

if [ "$(rpm -q --qf '%{VERSION}' cloudflare-warp 2>/dev/null || true)" != "$WARP_PIN" ]; then
    echo "Installing Cloudflare WARP ${WARP_PIN} (pinned, clean deps)..."
    if ! (
        set -eo pipefail
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        curl -fSL --max-time 120 -o "$tmp/warp.rpm" "$WARP_URL"
        echo "${WARP_SHA256}  $tmp/warp.rpm" | sha256sum -c -
        sudo dnf install -y --setopt=localpkg_gpgcheck=0 "$tmp/warp.rpm"
        sudo systemctl enable --now warp-svc.service
    ); then
        echo "WARNING: cloudflare-warp install failed (network, checksum, or packaging change?); skipping" >&2
    fi
fi
{{- end }}
```

- [ ] **Step 2: Verify the script still renders and is valid bash**

```bash
chezmoi execute-template < .chezmoiscripts/run_onchange_before_01-install-packages.sh.tmpl | bash -n && echo "OK bash"
```
Expected: `OK bash` (current data is `work`, so the WARP block renders and is syntax-checked).

- [ ] **Step 3: Confirm the new mechanics rendered and the old hack is gone**

```bash
chezmoi execute-template < .chezmoiscripts/run_onchange_before_01-install-packages.sh.tmpl \
  | rg -n 'rpm -U --nodeps|dnf download|/etc/yum.repos.d/cloudflare-warp.repo\b.*tee'  # expect no install-time matches
chezmoi execute-template < .chezmoiscripts/run_onchange_before_01-install-packages.sh.tmpl \
  | rg -n 'sha256sum -c|dnf install -y --setopt=localpkg_gpgcheck=0|2026.3.846.0'      # expect 3 matches
```
Expected: first command finds no `rpm -U --nodeps` or `dnf download`; second finds the checksum check, the dnf install, and the pinned version.

- [ ] **Step 4: Commit**

```bash
git add .chezmoiscripts/run_onchange_before_01-install-packages.sh.tmpl
git commit -m "warp: pin clean install (sha256, dnf deps), drop repo and --nodeps"
```

---

### Task 4: Final review and push

**Files:** none (verification + publish)

- [ ] **Step 1: Scoped chezmoi diff for the waybar targets (no 1Password needed)**

```bash
chezmoi diff ~/.config/waybar
```
Expected: shows `vpn-status.sh` content change, `warp-toggle.sh` removed, `vpn-toggle.sh` added, and the `config.jsonc` `on-click` line change. (A full `chezmoi diff` would prompt for 1Password via other templates; keep it scoped.)

- [ ] **Step 2: Confirm the working tree is clean and review the log**

```bash
git status -s            # expect empty
git log --oneline -5
```
Expected: no uncommitted changes; the three feature commits plus the earlier spec commit are present.

- [ ] **Step 3: Push to main**

WireGuard/work git identity is via 1Password; pushing uses the github SSH key, which needs the agent loaded once per session. If push fails with a key/permission error, the user runs `! ssh-add ~/.ssh/id_github` (passphrase prompt) in the session, then re-run:

```bash
git push origin main
```
Expected: push succeeds.

- [ ] **Step 4: Note deferred apply**

`chezmoi apply` is intentionally NOT run here (it needs 1Password). On the user's next apply: `~/.config/waybar/warp-toggle.sh` is removed, `vpn-toggle.sh` is written, `vpn-status.sh` is re-rendered, and (on a re-provision) the WARP block converges to the pinned version. State this in the final summary to the user.

---

## Self-Review

**Spec coverage:**
- Role-split `vpn-status.sh` (WARP work / nmcli personal, shared LAN fallback) -> Task 1. ✓
- Rename `warp-toggle.sh` -> `vpn-toggle.sh`, role-split, `config.jsonc` on-click repoint -> Task 2. ✓
- Honest header comments dropping "useful everywhere" language -> Tasks 1 & 2 Step 1 (new comments). ✓
- WARP pinned install: version + SHA256 pin, no repo, stale-repo removal, `dnf install --setopt=localpkg_gpgcheck=0`, converge-on-version guard, `systemctl enable --now`, rewritten comment -> Task 3. ✓
- Tray-mask unaffected -> not touched (correct). ✓
- Validation via render + `sh -n`/`bash -n`, scoped `chezmoi diff`, no apply -> Tasks 1-4. ✓
- Deployment: source-only, commit, push; rename cleanup on next apply -> Task 4. ✓

**Placeholder scan:** No TBD/TODO; all script bodies and commands are complete and literal.

**Type/name consistency:** `vpn-status.sh` / `vpn-toggle.sh` target names, `WARP_PIN` / `WARP_SHA256` / `WARP_URL` variable names, and the `~/.config/waybar/vpn-toggle.sh` on-click path are consistent across tasks and match `config.jsonc`.
