# Sway office-dock layout: design

> **Revised 2026-05-20.** The original design called for a true 3-way mirror
> on lid-open, implemented with sway's `output ... mirror <ref>` directive.
> During the implementation smoke test (Task 1 in the plan), sway 1.11 on
> Fedora 43 returned `Invalid output subcommand: mirror` — that directive
> doesn't exist in sway core. Adding it via `wl-mirror` was offered as an
> option but the user chose to drop the mirror requirement entirely in favour
> of an **always-split layout**: workspaces 1-5/6-10 are pinned to the Dells
> regardless of lid state, with `eDP-1` as a fallback when the Dells aren't
> present. The lid-event handling reduces to "enable/disable `eDP-1`," which
> the existing `50-lid.conf` (commit e44c7f2) already does — no new script,
> no `mirror` directives. The sections below are the revised design. The
> original-design rationale is preserved in the git history of this file
> (pre-revision: commit 64b8db4) for context.

**Date:** 2026-05-20 (revised same day)
**Status:** Approved
**Scope:** Work laptop only (`.machine_role == "work"`).

## Problem

The work laptop is docked to two Dell U2417H monitors in the office. Behaviour
the user wants (post-revision):

- **Docked, either lid state:** workspaces **1-5** live on the **left** Dell,
  **6-10** on the **right** Dell. Lid state is independent of workspace
  placement.
- **Lid open** (docked): the laptop panel is just an additional screen on the
  right (sway's default placement). Useful for ad-hoc workspaces (11+) or
  workspaces explicitly moved there.
- **Lid closed** (docked): laptop panel off; nothing else changes.
- **Undocked** (Dells not present): all 10 workspaces fall back to `eDP-1` via
  the workspace preferred-output list.
- **Other external monitors** (e.g. a TV): default sway behaviour — they
  don't match the Dell output blocks, so the workspace pinning doesn't fire
  for them.
- **No external + lid closed:** suspend (existing logind default;
  `HandleLidSwitchDocked=ignore` only suppresses suspend when docked).

The existing `private_dot_config/sway/config.d/50-lid.conf` (committed in
e44c7f2) already disables `eDP-1` on lid close. This spec adds the docking
layout on top of that; the lid file itself is unchanged.

## Hardware identifiers

Captured live from `swaymsg -t get_outputs` on 2026-05-20:

| Slot   | sway name | Make/Model              | Serial         | Physical position |
|--------|-----------|-------------------------|----------------|-------------------|
| LEFT   | DP-6      | Dell Inc. DELL U2417H   | 5K9YD88IAS0L   | x=0               |
| RIGHT  | DP-7      | Dell Inc. DELL U2417H   | 5K9YD8B7CYZW   | x=1920            |
| Laptop | eDP-1     | Sharp 0x1548            | (unknown)      | x=0 (1920x1200)   |

`DP-6`/`DP-7` slot names are not stable across reboots; the **make + model +
serial** triple is. Same model on both Dells, so the serial is required to
disambiguate left vs right.

## Design

### Approach: static `output`/`workspace` directives only

Two pieces:

1. **Office-Dell `output` blocks** pin each Dell by `"<make> <model> <serial>"`
   to a known position (left at x=0, right at x=1920). A non-office monitor
   never matches these blocks and falls through to sway's default placement.

2. **Workspace preferred-output lists**: workspaces 1-5 prefer the left Dell
   then fall back to `eDP-1`; workspaces 6-10 prefer the right Dell then fall
   back to `eDP-1`. With the Dells connected, workspaces always land on them
   regardless of lid state. Undocked, they fall back to the laptop panel. Sway
   auto-migrates workspaces when a preferred output appears or disappears.

The lid event handling stays as-is in `50-lid.conf` from commit e44c7f2 (two
`bindswitch` lines that enable/disable `eDP-1`). With workspaces pinned to the
Dells when they're present, the lid only needs to control the laptop panel —
no script needed.

Rejected alternatives (this revision):
- **Use `wl-mirror` to fake the original 3-way mirror.** Two extra long-lived
  processes per session, ~1 frame of capture latency, package dependency.
  User declined.
- **Original design with `output ... mirror eDP-1`.** Not supported by sway
  1.11; the directive doesn't exist.

### File layout (chezmoi source)

- `private_dot_config/sway/config.d/40-outputs-work.conf.tmpl` — new. Wrapped
  in `{{ if eq .machine_role "work" }}`. Contains the two office Dell `output`
  blocks and the ten `workspace N output ...` assignments.
- `private_dot_config/sway/config.d/50-lid.conf` — **unchanged from e44c7f2.**
  No revision needed: enable/disable `eDP-1` on lid switch is exactly the
  required behaviour.

Filename follows the existing `config.d/NN-name.conf` convention already used
by `60-bindings-screenshot.conf`.

### File contents (sketch)

`40-outputs-work.conf.tmpl`:

```
{{- if eq .machine_role "work" -}}
# Office dock: two identical Dell U2417Hs, pinned by serial because the same
# make+model can't be disambiguated otherwise. Position is fixed so the layout
# is stable across reconnects.
output "Dell Inc. DELL U2417H 5K9YD88IAS0L" pos 0    0
output "Dell Inc. DELL U2417H 5K9YD8B7CYZW" pos 1920 0

# Workspaces 1-5 prefer the LEFT Dell, 6-10 prefer the RIGHT Dell. Fall back
# to eDP-1 when undocked. Sway auto-migrates workspaces when a preferred
# output appears or disappears.
workspace 1  output "Dell Inc. DELL U2417H 5K9YD88IAS0L" eDP-1
workspace 2  output "Dell Inc. DELL U2417H 5K9YD88IAS0L" eDP-1
workspace 3  output "Dell Inc. DELL U2417H 5K9YD88IAS0L" eDP-1
workspace 4  output "Dell Inc. DELL U2417H 5K9YD88IAS0L" eDP-1
workspace 5  output "Dell Inc. DELL U2417H 5K9YD88IAS0L" eDP-1
workspace 6  output "Dell Inc. DELL U2417H 5K9YD8B7CYZW" eDP-1
workspace 7  output "Dell Inc. DELL U2417H 5K9YD8B7CYZW" eDP-1
workspace 8  output "Dell Inc. DELL U2417H 5K9YD8B7CYZW" eDP-1
workspace 9  output "Dell Inc. DELL U2417H 5K9YD8B7CYZW" eDP-1
workspace 10 output "Dell Inc. DELL U2417H 5K9YD8B7CYZW" eDP-1
{{- end -}}
```

`50-lid.conf`: unchanged from e44c7f2. The two `bindswitch` lines that
enable/disable `eDP-1` on lid open/close are sufficient.

### Behaviour matrix

| Scenario                                  | Result                                                                 |
|-------------------------------------------|------------------------------------------------------------------------|
| Office Dells + lid open                   | WS 1-5 on left Dell, WS 6-10 on right Dell, `eDP-1` is an extra screen on the right. |
| Office Dells + lid closed                 | WS 1-5 on left Dell, WS 6-10 on right Dell, `eDP-1` off.               |
| Office Dells, hotplug (connect/disconnect)| Sway auto-migrates the relevant workspaces on/off the Dells.            |
| TV (or unknown monitor) + lid open        | Default extend. TV is just an extra output. WS 1-10 stay on `eDP-1` (Dells absent, fallback fires). |
| TV + lid closed                           | `eDP-1` off. Workspaces that had been on `eDP-1` migrate to whatever output remains. |
| No external + lid closed                  | logind default: suspend (`HandleLidSwitchDocked=ignore` only applies docked). |
| `swaymsg reload`                          | Static `output`/`workspace` directives re-apply; bindswitch with `--reload` re-fires; ends in correct state. |
| Sway startup                              | Static directives apply, bindswitch fires once with current lid state. |

### Caveats

- The Dells (1920×1080) and the laptop panel (1920×1200) have different
  heights. When the lid is open with the laptop placed to the right of the
  Dells (sway's default), there's a small vertical mismatch at the
  Dell→laptop boundary. Acceptable, the user has said the layout is fine.
- A workspace not in the 1-10 range has no preferred-output assignment and
  will be created on whichever output sway picks (usually the focused one).
- If only one of the two Dells is connected (e.g. only the left), workspaces
  6-10 fall through to `eDP-1` when the lid is open; lid-closed they'd
  migrate to the left Dell since it's the only active output. Edge case,
  not worth special-casing.

## Out of scope

- A separate output config for the **personal** laptop. The user mentioned
  they'll want one; it will be a sibling file (e.g.
  `40-outputs-personal.conf.tmpl`) under a different role guard, designed
  separately.
- Anything that touches `logind.conf`. Current defaults are correct.
- Audio routing between docked-out HDMI/DP and the laptop speakers.
