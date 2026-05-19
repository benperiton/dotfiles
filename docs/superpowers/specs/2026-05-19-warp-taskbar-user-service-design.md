# Cloudflare WARP tray (warp-taskbar) on work machines: design

**Date:** 2026-05-19
**Status:** Approved

## Problem

The `cloudflare-warp` package (installed work-only by
`run_onchange_before_01-install-packages.sh.tmpl`, see
`2026-05-19-cloudflare-warp-chezmoi-design.md`) ships a system-tray applet,
`warp-taskbar.service`. Unlike `warp-svc.service` (system service, auto-enabled
by the package), `warp-taskbar.service` is a **user** service and is **not**
enabled by default. The user wants chezmoi to enable it on work machines so the
WARP tray icon appears (the box runs waybar, whose `tray` module renders it).

This is the follow-up the WARP install spec deliberately left out of scope
("no systemd unit work in chezmoi"); it is now in scope, scoped to the user
service only.

## Design (Approach A)

User-service enablement already has one home:
`.chezmoiscripts/run_once_after_09-setup-user-services.sh` (a plain `.sh`,
`run_once_after`), which does `systemctl --user daemon-reload` then loops
`ssh-agent.service` / `tmux.service` with an `is-enabled` guard and
`enable --now`. Script `01` (the `run_onchange_before` WARP install) runs
before script `09` within a single `chezmoi apply`, so by the time `09` runs
the package and its user unit exist. This script is therefore the correct,
pattern-consistent home; script `01` is not touched.

### 1. Convert the script to a template

`git mv .chezmoiscripts/run_once_after_09-setup-user-services.sh
.chezmoiscripts/run_once_after_09-setup-user-services.sh.tmpl`

The existing body contains no `{{ }}`, so template rendering is identity-safe.
chezmoi tracks `run_once_` scripts by a hash of the rendered content; adding
the block below changes that content, so the script re-runs exactly once on
the next `chezmoi apply` (the existing `ssh-agent`/`tmux` loop is idempotent
via its `is-enabled` guard, so re-running it is harmless).

### 2. Append a work-gated block after the existing loop

```
{{- if eq .machine_role "work" }}

# Cloudflare WARP tray (work only). The WARP install (script 01) is
# warn-and-continue, so cloudflare-warp and its user unit may be absent on a
# Fedora-incompatible box; the `rpm -q` guard prevents that from aborting this
# script. `systemctl --user enable` needs no display and is idempotent. The
# start is tolerated: although work machines are never headless, `chezmoi
# apply` may run over SSH/TTY with no Wayland session, and the tray is only
# useful in a graphical session, so on failure it simply autostarts at the
# next graphical login (the unit is enabled regardless).
if rpm -q cloudflare-warp &>/dev/null \
     && ! systemctl --user is-enabled warp-taskbar.service &>/dev/null; then
    echo "Enabling warp-taskbar.service"
    systemctl --user enable warp-taskbar.service
    systemctl --user start warp-taskbar.service \
        || echo "  (warp-taskbar will start at next graphical login)" >&2
fi
{{- end }}
```

Behavior:

- **work + package present + not yet enabled:** enable (durable: autostarts at
  graphical login), then best-effort start now. A no-display start failure
  prints a note and does not abort (`|| echo ... >&2`, exit 0).
- **work + package absent** (WARP install skipped/failed on a
  Fedora-incompatible box): `rpm -q` fails, block is a no-op, no error.
- **work + already enabled:** `is-enabled` guard makes the block a no-op,
  matching the existing loop's idiom.
- **personal / any non-work:** the `{{- if }}` renders the block to nothing.

`run_once_` re-runs only on content change, so the best-effort start is
effectively one-shot; the durable guarantee is "enabled, therefore autostarts
at the next graphical login." This is accepted.

The block uses the existing loop's `is-enabled` guard idiom for consistency;
it intentionally does **not** use `enable --now` (the loop's form for the
headless-safe `ssh-agent`/`tmux`) because a tray applet started in a
non-graphical apply context would fail under `set -euo pipefail`.

## Out of scope

- No change to `run_onchange_before_01-install-packages.sh.tmpl` or the WARP
  install / repo logic.
- No `warp-svc` work (the package enables the system service itself).
- No enrollment / connection / `warp-cli` automation (still manual, per the
  WARP install spec).
- No waybar config change (its `tray` module already exists and renders SNI
  icons; nothing to add).
- No change to the existing `ssh-agent`/`tmux` loop behavior.

## Verification

`chezmoi execute-template` renders of
`run_once_after_09-setup-user-services.sh.tmpl`:

- **work** render: contains the `warp-taskbar.service` block, the
  `rpm -q cloudflare-warp` guard, `systemctl --user enable
  warp-taskbar.service`, and the tolerated `systemctl --user start ... ||`
  line. The existing `ssh-agent`/`tmux` loop is still present and unchanged.
- **personal** render: the string `warp-taskbar` appears nowhere; the
  `ssh-agent`/`tmux` loop is still present and unchanged.
- The work render is valid bash (`bash -n`).
- No em-dash or en-dash anywhere in the file (user global rule).
- `git mv` is used so file history is preserved; `chezmoi diff` shows only the
  rename + the appended block, no other file.
- Assumption to confirm on the first real work-box apply (it cannot be checked here, since the package is work-only and absent on every machine in reach): `systemctl --user is-enabled warp-taskbar.service` must NOT report `static`. The enable-based approach relies on the unit having an `[Install]` section, which matches Cloudflare's documented setup (`systemctl --user enable --now warp-taskbar`; that command fails on a `static` unit, so the documented instruction itself is evidence the unit is enable-able). If it ever reports `static`, switch to `systemctl --user add-wants graphical-session.target warp-taskbar.service` plus a `start`, and replace the `is-enabled` guard with an `is-active` check.
