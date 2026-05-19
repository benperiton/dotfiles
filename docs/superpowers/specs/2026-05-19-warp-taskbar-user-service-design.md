# Cloudflare WARP tray (warp-taskbar) on work machines: design

**Date:** 2026-05-19
**Status:** Approved

**Revision (2026-05-19):** The initial design used `systemctl --user enable`
guarded by `! is-enabled`. Code-quality review established empirically that on
this systemd, `systemctl --user enable` on a unit with no `[Install]` section
returns 0 (a no-op) and `systemctl --user is-enabled` returns 0 printing
`static` for such a unit. So if `warp-taskbar.service` ships `static`, the
`! is-enabled` guard is false and the whole block is silently skipped (the tray
is never wired up, and the apply still reports success). That approach is
superseded below by `systemctl --user add-wants graphical-session.target`
guarded by `! is-active`, which is correct regardless of the unit's install
type (it works for both `[Install]` and `static` units) and removes the
unverifiable assumption entirely. All sections below describe the revised
approach.

## Problem

The `cloudflare-warp` package (installed work-only by
`run_onchange_before_01-install-packages.sh.tmpl`, see
`2026-05-19-cloudflare-warp-chezmoi-design.md`) ships a system-tray applet,
`warp-taskbar.service`. Unlike `warp-svc.service` (system service, auto-enabled
by the package), `warp-taskbar.service` is a **user** service and is **not**
started by default. The user wants chezmoi to set it up on work machines so the
WARP tray icon appears (the box runs waybar, whose `tray` module renders it).

This is the follow-up the WARP install spec deliberately left out of scope
("no systemd unit work in chezmoi"); it is now in scope, scoped to the user
service only.

## Design (Approach A)

User-service setup already has one home:
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
# Fedora-incompatible box; the rpm -q guard prevents that from aborting this
# script. add-wants graphical-session.target wires autostart whether
# warp-taskbar.service ships with an [Install] section or as a static unit (a
# plain enable would silently no-op on a static unit, since is-enabled then
# returns 0), and it needs no display. The start is tolerated: although work
# machines are never headless, chezmoi apply may run over SSH/TTY with no
# Wayland session, and the tray is only useful in a graphical session, so on
# failure it autostarts at the next graphical login via the wants symlink.
if rpm -q cloudflare-warp &>/dev/null \
     && ! systemctl --user is-active warp-taskbar.service &>/dev/null; then
    echo "Wiring warp-taskbar.service into graphical-session.target"
    systemctl --user add-wants graphical-session.target warp-taskbar.service
    systemctl --user start warp-taskbar.service \
        || echo "  (warp-taskbar will start at next graphical login)" >&2
fi
{{- end }}
```

Behavior:

- **work + package present + not yet active:** `add-wants` creates the
  `graphical-session.target` wants symlink (durable autostart at graphical
  login; works for both `[Install]` and `static` units), then a best-effort
  start now. A no-display start failure prints a note and does not abort
  (`|| echo ... >&2`, exit 0).
- **work + package absent** (WARP install skipped/failed on a
  Fedora-incompatible box): `rpm -q` fails, block is a no-op, no error.
- **work + already active:** the `is-active` guard makes the block a no-op.
- **personal / any non-work:** the `{{- if }}` renders the block to nothing.

`run_once_` re-runs only on content change, so the best-effort start is
effectively one-shot; the durable guarantee is the `graphical-session.target`
wants symlink created by `add-wants`, which autostarts the tray at the next
graphical login regardless of whether the unit has an `[Install]` section.
This is accepted.

The block deliberately uses `add-wants graphical-session.target` rather than
the loop's `enable --now`: (a) `enable` is install-type-sensitive (a `static`
unit makes `is-enabled` return 0 and a plain `enable` a silent no-op), whereas
`add-wants` works for both `[Install]` and `static` units; (b) `--now` would
start a tray applet in a possibly non-graphical apply context and fail under
`set -euo pipefail`. The `is-active` guard replaces the loop's `is-enabled`
guard accordingly, and is idempotent (re-adding an existing wants symlink is a
no-op).

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
  `rpm -q cloudflare-warp` guard, the `! systemctl --user is-active
  warp-taskbar.service` guard, `systemctl --user add-wants
  graphical-session.target warp-taskbar.service`, and the tolerated
  `systemctl --user start ... ||` line. The existing `ssh-agent`/`tmux` loop is
  still present and unchanged. The strings `is-enabled warp-taskbar` and
  `enable warp-taskbar` appear nowhere (the revised approach uses neither).
- **personal** render: the string `warp-taskbar` appears nowhere; the
  `ssh-agent`/`tmux` loop is still present and unchanged.
- The work render is valid bash (`bash -n`).
- No em-dash or en-dash anywhere in the file (user global rule).
- `git mv` is used so file history is preserved; `chezmoi diff` shows only the
  rename + the appended block, no other file.
- Confirm on the first real work-box apply (the only thing not verifiable
  here, since the package is work-only and absent on every machine in reach):
  the WARP tray icon appears in waybar and `systemctl --user is-active
  warp-taskbar.service` reports active within the graphical session. The
  `add-wants` approach is install-type-independent, so no `static`-vs-`[Install]`
  assumption remains; this check is just confirming the tray actually shows up
  under Sway/waybar.
