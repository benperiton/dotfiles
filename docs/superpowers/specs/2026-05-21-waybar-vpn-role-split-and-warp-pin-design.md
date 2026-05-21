# Waybar VPN module role-split + WARP pinned install

## Problem

Two related warts left over from the WARP work on 2026-05-20:

1. **Waybar VPN module is implicitly cross-machine.** `vpn-status.sh` and
   `warp-toggle.sh` were written to be "useful everywhere from a single config":
   they probe `command -v warp-cli` at runtime and fall back to nmcli WireGuard
   (and then LAN) when WARP is absent. WARP only exists on `work` machines (the
   rpm install in script 01 is already `work`-gated), so on a `personal` box the
   scripts already silently behave as a WireGuard indicator. This works, but it
   relies on a runtime probe rather than `machine_role`, which is out of step
   with this repo's two-axis model where everything branches explicitly on
   `machine_role`. Each script also carries a dead branch and header comments
   describing the very "single config everywhere" design we are retiring.

2. **WARP installs via an `rpm -U --nodeps` hack.** Script 01 adds the
   `cloudflare-warp` repo, downloads the *latest* rpm, and installs it with
   `--nodeps` because the current rpm hard-`Requires` `webkit2gtk3`, which
   Fedora 43 removed (it ships only `webkit2gtk4.1` / `webkitgtk6.0`). The
   dependency is over-declared (none of the WARP binaries link libwebkit2gtk),
   so the daemon and CLI work without it, but the install is unclean and the
   enabled repo means a future `dnf upgrade` would try (and fail) to pull the
   `webkit2gtk3`-requiring latest.

   Empirically verified: the pinned version `2026.3.846.0`
   (`https://downloads.cloudflareclient.com/v1/download/fedora34-intel/version/2026.3.846.0`)
   `Requires` only `ca-certificates dbus desktop-file-utils glibc iproute
   libpcap nftables nss-tools` (plus `/bin/sh` and rpmlib) - no webkit at all,
   all satisfiable from Fedora 43 stock repos. It can install cleanly via `dnf`.

## Goals

- The waybar VPN module's behaviour is selected by `machine_role`, not by a
  runtime `warp-cli` probe: WARP logic on `work`, WireGuard logic on `personal`.
- Each rendered script contains only the branch relevant to its role (no dead
  code) and honest header comments.
- Visible behaviour is unchanged from today on both roles (work: WARP status +
  toggle; personal: WireGuard status + NetworkManager on click).
- WARP installs cleanly with normal dependency resolution (no `--nodeps`),
  pinned to the vetted `2026.3.846.0`, with no enabled repo that could break a
  later `dnf upgrade`.

## Non-goals

- Removing the `custom/vpn` module on `personal` (the user wants the WireGuard
  indicator kept).
- Changing the personal click action to actually toggle WireGuard up/down;
  it stays "open NetworkManager" (`nm-connection-editor`).
- Adding split-vs-full-tunnel labelling to the personal tooltip (possible later
  parity nicety, explicitly out of scope here).
- Auto-upgrading WARP. The pin is deliberate; bumping is a manual edit.
- Restoring GPG *authenticity* verification for WARP (see Risks).

## Design

### Part 1 - Role-split waybar VPN scripts (`private_dot_config/waybar/`)

`.config/waybar` is already `.chezmoiignore`d on `headless`, so only `work` and
`personal` (desktop/laptop) render these.

**`executable_vpn-status.sh` -> `executable_vpn-status.sh.tmpl`**

Shared, outside any conditional: shebang, header comment, `LOCK_OPEN`/
`LOCK_SHUT` glyphs, the best-effort public-IP fetch + sanitise, and the
`emit()` helper.

- `{{ if eq .machine_role "work" }}`: the existing WARP branch (Connected /
  Connecting / Disconnecting / Unable to Connect, with split-vs-full detection
  via `warp-cli settings`), then the LAN fallback. The nmcli WireGuard branch is
  dropped (dead on work).
- `{{ else }}`: the existing nmcli VPN/WireGuard branch, then the LAN fallback.
  The WARP branch is dropped (dead on personal).
- `{{ end }}`

**`executable_warp-toggle.sh` -> `executable_vpn-toggle.sh.tmpl`** (renamed so it
is not WARP-named on a personal box)

- `{{ if eq .machine_role "work" }}`: `warp-cli` connect/disconnect toggle,
  then `pkill -RTMIN+8 waybar` to repaint immediately.
- `{{ else }}`: `nm-connection-editor` (no repaint signal needed; it is a GUI
  dialog with no instant state change).
- `{{ end }}`

**`config.jsonc`** (stays a plain, non-template file): in the `custom/vpn`
block, change `on-click` from `~/.config/waybar/warp-toggle.sh` to
`~/.config/waybar/vpn-toggle.sh`. `exec` already points at
`~/.config/waybar/vpn-status.sh` and is unchanged. The module appears on both
roles exactly as now.

Header comments in both scripts are rewritten to drop the "useful everywhere /
falls back when WARP absent" language and state that the file renders per
`machine_role`.

### Part 2 - Pinned clean WARP install

In `.chezmoiscripts/run_onchange_before_01-install-packages.sh.tmpl`, replace the
contents of the existing `{{ if eq .machine_role "work" }}` WARP block:

- Define `PIN=2026.3.846.0` and
  `SHA256=a272001189ffdfe6886b5520d396d17c99065fb66f9aaf3a48e36ca6e0fa6358`
  (artifact size 57566835 bytes, verified 2026-05-21).
- Guard converges on version, not mere presence:
  install when `rpm -q --qf '%{VERSION}' cloudflare-warp` != `$PIN`.
- Idempotently remove the stale repo from the old approach:
  `sudo rm -f /etc/yum.repos.d/cloudflare-warp.repo` (an enabled repo would let
  `dnf upgrade` attempt the broken latest).
- Inside the existing warn-and-continue subshell:
  - `curl -fSL --max-time 120 -o "$tmp/warp.rpm"` the pinned URL.
  - Verify integrity: `printf '%s  %s\n' "$SHA256" "$tmp/warp.rpm" | sha256sum -c -`,
    abort the subshell on mismatch.
  - `sudo dnf install -y --setopt=localpkg_gpgcheck=0 "$tmp/warp.rpm"`. The
    `--setopt` scopes the unsigned exception to just this local file; Fedora-repo
    dependencies remain GPG-verified. No `--nodeps`.
  - `sudo systemctl enable --now warp-svc.service` (unchanged).
- Drop the `rpm --import` of the Cloudflare key and the `dnf download` from the
  repo (no repo now). Keep the whole thing `work`-gated.
- Rewrite the comment to explain: the pin to a vetted version predating the
  over-declared `webkit2gtk3` dep, the unsigned-artifact / SHA256 tradeoff, why
  no repo is added, and how to bump (edit `PIN` + `SHA256`; run_onchange re-runs).

The tray-mask (`run_after_20-warp-tray-mask.sh.tmpl`) is unaffected and stays
`work`-gated.

## Validation (no `chezmoi apply`)

- `chezmoi execute-template` each new `.tmpl` rendered for both roles, and
  `sh -n` the output, to confirm both branches are valid POSIX shell.
- `chezmoi execute-template` the install script and `bash -n` it.
- `chezmoi diff` to eyeball the rendered changes.

Actual deployment (`chezmoi apply`, which needs 1Password) and the live WARP
install are the user's call later; not part of this change.

## Risks / tradeoffs

- **Loss of GPG authenticity for WARP.** The direct-download artifact is not
  GPG-signed (`rpm -Kv` shows digests only; all signature headers `(none)`). We
  substitute an HTTPS fetch + pinned SHA256 for tamper-evidence on the vetted
  bytes. There is no signed copy of this clean version available (the signed
  repo serves only the broken latest), so this is the pragmatic ceiling.
  Accepted by the user.
- **Pin goes stale.** No automatic WARP updates. Bumping is a deliberate
  two-line edit. Matches the prior "manual bump" reality, now cleaner.
- **Downgrade edge.** If a newer `cloudflare-warp` is somehow already installed,
  `dnf install` of the pin will not downgrade; that would need a manual
  `dnf downgrade`. Not expected in normal flow.

## Deployment note

Per the chezmoi workflow, this change is made in source, committed, and pushed
to `main`; it is not applied here. The rename means that on the next
`chezmoi apply`, the now-unmanaged `~/.config/waybar/warp-toggle.sh` is removed
and `vpn-toggle.sh` is written.
