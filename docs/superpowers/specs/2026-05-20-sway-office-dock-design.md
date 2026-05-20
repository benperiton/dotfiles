# Sway office-dock layout: design

**Date:** 2026-05-20
**Status:** Approved
**Scope:** Work laptop only (`.machine_role == "work"`).

## Problem

The work laptop is docked to two Dell U2417H monitors in the office. Behaviour
the user wants:

- **Lid open** (docked): true 3-way mirror — the laptop panel and both Dells
  show the same image; all 10 workspaces live on `eDP-1`.
- **Lid closed** (docked): laptop panel off, workspaces **1-5** on the **left**
  Dell, **6-10** on the **right** Dell.
- **Other external monitors** (e.g. a meeting-room TV at someone's house):
  default sway behaviour — extend desktop, no mirror, no workspace split.
- **No external + lid closed:** suspend (existing logind default;
  `HandleLidSwitchDocked=ignore` only suppresses suspend when docked).

The existing `private_dot_config/sway/config.d/50-lid.conf` (committed in
e44c7f2) already disables `eDP-1` on lid close. This spec replaces it with the
full docking story.

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

### Approach: static `output`/`workspace` directives + lid script

Three pieces:

1. **Office-Dell `output` blocks** pin each Dell by `"<make> <model> <serial>"`
   and configure it to mirror `eDP-1`. A non-office monitor never matches these
   blocks and falls through to sway's default (extend desktop).

2. **Workspace preferred-output lists** (`workspace N output eDP-1 "<dell>"`)
   put every workspace on `eDP-1` while the lid is open. When `eDP-1` is
   disabled, sway automatically migrates each workspace to its second-choice
   Dell. When `eDP-1` comes back, sway migrates them back. No manual `move
   workspace` is required.

3. **`bindswitch` script** runs on lid open/close, clears or re-establishes the
   mirror, and toggles `eDP-1`. The Dell directives in the script are guarded
   against "not currently connected" by simply issuing the `swaymsg` calls
   (sway logs a warning and continues if the named output isn't present).

Rejected alternatives:
- **All-dynamic via one script that probes outputs at runtime** — more moving
  parts, harder to read what's going on from the sway config alone.
- **Per-output mode lines only, no script** — too coarse, can't both
  mirror-on-open and split-on-close from static config.

### File layout (chezmoi source)

- `private_dot_config/sway/config.d/40-outputs-work.conf.tmpl` — new. Wrapped
  in `{{ if eq .machine_role "work" }}`. Contains the two office Dell `output`
  blocks and the ten `workspace N output ...` assignments.
- `private_dot_config/sway/config.d/50-lid.conf` — replaced. Now just the two
  `bindswitch ... exec lid.sh open|close` lines. Not templated; the lid script
  itself no-ops when its targets aren't present, so the file is safe to deploy
  on any machine with a lid switch. (A keyboard-only desktop has no lid switch
  to fire it, so it's harmless even there.)
- `private_dot_config/sway/scripts/executable_lid.sh` — new. The toggle script.

Filenames follow the existing `config.d/NN-name.conf` convention already used
by `60-bindings-screenshot.conf`. The `executable_` chezmoi prefix makes
`lid.sh` deploy as +x.

### File contents (sketch)

`40-outputs-work.conf.tmpl`:

```
{{- if eq .machine_role "work" -}}
# Office dock: two identical Dell U2417Hs, pinned by serial.
# When connected and the lid is open they mirror the laptop panel;
# the lid script disables the mirror on close (see scripts/lid.sh).
output "Dell Inc. DELL U2417H 5K9YD88IAS0L" pos 0    0 mirror eDP-1
output "Dell Inc. DELL U2417H 5K9YD8B7CYZW" pos 1920 0 mirror eDP-1

# Workspace placement: first choice eDP-1 (lid open), fall back to the
# appropriate Dell when the lid closes and eDP-1 is disabled.
workspace 1  output eDP-1 "Dell Inc. DELL U2417H 5K9YD88IAS0L"
workspace 2  output eDP-1 "Dell Inc. DELL U2417H 5K9YD88IAS0L"
workspace 3  output eDP-1 "Dell Inc. DELL U2417H 5K9YD88IAS0L"
workspace 4  output eDP-1 "Dell Inc. DELL U2417H 5K9YD88IAS0L"
workspace 5  output eDP-1 "Dell Inc. DELL U2417H 5K9YD88IAS0L"
workspace 6  output eDP-1 "Dell Inc. DELL U2417H 5K9YD8B7CYZW"
workspace 7  output eDP-1 "Dell Inc. DELL U2417H 5K9YD8B7CYZW"
workspace 8  output eDP-1 "Dell Inc. DELL U2417H 5K9YD8B7CYZW"
workspace 9  output eDP-1 "Dell Inc. DELL U2417H 5K9YD8B7CYZW"
workspace 10 output eDP-1 "Dell Inc. DELL U2417H 5K9YD8B7CYZW"
{{- end -}}
```

`50-lid.conf` (replaces the current contents):

```
# Lid switch: see scripts/lid.sh for the work-dock-aware logic.
# Non-work machines: the script still disables eDP-1 on close and re-enables
# on open; the Dell-specific lines are no-ops when those outputs aren't
# present.
bindswitch --reload --locked lid:on  exec ~/.config/sway/scripts/lid.sh close
bindswitch --reload --locked lid:off exec ~/.config/sway/scripts/lid.sh open
```

`executable_lid.sh`:

```sh
#!/bin/sh
# Toggle the laptop panel and the office-Dell mirror together on lid events.
# Called by bindswitch in 50-lid.conf.
#   lid.sh open   - re-enable eDP-1; re-mirror the Dells onto it (if present).
#   lid.sh close  - clear the Dell mirror; disable eDP-1. Workspaces migrate
#                   automatically per the workspace preferred-output lists in
#                   40-outputs-work.conf.

set -u
LEFT='Dell Inc. DELL U2417H 5K9YD88IAS0L'
RIGHT='Dell Inc. DELL U2417H 5K9YD8B7CYZW'

case "${1:-}" in
  open)
    swaymsg "output eDP-1 enable"
    swaymsg "output \"$LEFT\"  pos 0    0 mirror eDP-1"
    swaymsg "output \"$RIGHT\" pos 1920 0 mirror eDP-1"
    ;;
  close)
    # Drop the mirror first so the Dells become independent outputs that can
    # host workspaces. `pos` without `mirror` clears the mirror state.
    swaymsg "output \"$LEFT\"  pos 0    0"
    swaymsg "output \"$RIGHT\" pos 1920 0"
    swaymsg "output eDP-1 disable"
    ;;
  *)
    echo "usage: $0 open|close" >&2
    exit 2
    ;;
esac
```

### Behaviour matrix

| Scenario                                  | Result                                                                 |
|-------------------------------------------|------------------------------------------------------------------------|
| Office Dells + lid open                   | All 3 screens mirror `eDP-1`. All workspaces on `eDP-1`.               |
| Office Dells + lid closed                 | `eDP-1` off. WS 1-5 on left Dell, WS 6-10 on right Dell.               |
| Office Dells, lid open while WS on Dells  | Workspaces auto-migrate back to `eDP-1`.                               |
| TV (or unknown monitor) + lid open        | Default extend. TV is just an extra output. `eDP-1` normal.            |
| TV + lid closed                           | `eDP-1` off. Anything that was on `eDP-1` moves to the TV.             |
| No external + lid closed                  | logind default: suspend (`HandleLidSwitchDocked=ignore` only applies docked). |
| `swaymsg reload` while lid closed         | `--reload` re-fires the bindswitch with current state; ends in correct state. |
| Sway startup with lid closed              | Bindswitch fires on startup with current state (sway behaviour).       |

### Caveats

- `eDP-1` is 1920×1200, the Dells are 1920×1080. The mirror is letterboxed
  (black bars top/bottom on the Dells). Accepted: mirror is a brief lid-open
  state.
- One DP-* slot may be unused on a non-work machine where neither Dell is
  attached; the script's Dell lines just log a warning from sway.
- The script depends on `swaymsg` being on `$PATH`. It runs in the sway user
  session, so this holds.
- The "clear mirror by re-setting `pos`" trick is documented sway behaviour
  (any non-`mirror` config takes the output out of mirror mode), but worth a
  quick live `swaymsg output "<dell>" pos 0 0` test during implementation in
  case a sway version regression bites.

## Out of scope

- A separate output config for the **personal** laptop. The user mentioned
  they'll want one; it will be a sibling file (e.g.
  `40-outputs-personal.conf.tmpl`) under a different role guard, designed
  separately.
- Anything that touches `logind.conf`. Current defaults are correct.
- Audio routing between docked-out HDMI/DP and the laptop speakers.
