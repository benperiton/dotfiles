# Sway office-dock layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the work laptop is docked to its two office Dell U2417Hs, mirror the laptop panel onto both Dells while the lid is open, and split workspaces 1-5/6-10 across the two Dells while the lid is closed. Other monitors (TV, projector) fall through to default sway extend behaviour.

**Architecture:** Three new chezmoi-managed files under `private_dot_config/sway/`. A work-role-gated `.tmpl` defines the two Dell output blocks (`mirror eDP-1`) and the ten workspace preferred-output assignments; a small POSIX script toggles the mirror and the panel together on lid events; `50-lid.conf` is rewritten to invoke that script via `bindswitch`. Sway's "first-available preferred output" rule does the workspace migration automatically when `eDP-1` is disabled.

**Tech Stack:** sway 1.x (Wayland compositor) with `swaymsg`/`bindswitch`, chezmoi (Go text/template), POSIX `/bin/sh`. Validation per the repo's CLAUDE.md is `chezmoi execute-template` + `sh -n` + `chezmoi diff`; deployment to `$HOME` is targeted `chezmoi apply <path>` (no 1Password prompts since these files don't reference `onepasswordRead`).

Spec: `docs/superpowers/specs/2026-05-20-sway-office-dock-design.md`.

**Pre-existing state:** commit `e44c7f2` shipped a minimal
`private_dot_config/sway/config.d/50-lid.conf` with two hard-coded
`bindswitch ... output eDP-1 disable|enable` lines. This plan replaces that
file's contents.

All commands run from the chezmoi source directory unless noted:
`cd ~/.local/share/chezmoi`.

---

### Task 1: Smoke-test the mirror-clear assumption

**Files:** none (live system probe). This task validates the central design
assumption — "setting `pos X 0` on a mirroring output drops it out of mirror
mode" — *before* we encode it in a script. If sway 1.x on Fedora 43 disagrees,
the script needs a different incantation.

- [ ] **Step 1: Capture current output state**

```bash
swaymsg -t get_outputs | jq -r '.[] | "\(.name) active=\(.active) make=\"\(.make)\" model=\"\(.model)\" serial=\"\(.serial)\""'
```

Expected: three rows, the two Dells `active=true` and `eDP-1` `active=false`
(lid currently closed). Record the make/model/serial of each Dell. They should
match what the design spec captured (`5K9YD88IAS0L` left, `5K9YD8B7CYZW`
right); if they don't, stop and update the spec before continuing.

- [ ] **Step 2: Open the lid and put both Dells into mirror mode**

Open the laptop lid (so `eDP-1` becomes available as a mirror source), then
issue the mirror commands:

```bash
swaymsg 'output eDP-1 enable'
swaymsg 'output "Dell Inc. DELL U2417H 5K9YD88IAS0L" pos 0    0 mirror eDP-1'
swaymsg 'output "Dell Inc. DELL U2417H 5K9YD8B7CYZW" pos 1920 0 mirror eDP-1'
```

Expected: each `swaymsg` returns `[{"success": true}]`. Visually: both Dells
now show the laptop's content.

- [ ] **Step 3: Verify mirror state via swaymsg**

```bash
swaymsg -t get_outputs | jq -r '.[] | select(.name | startswith("DP-")) | "\(.name)  mirroring=\(.current_mode // "?")  rect=\(.rect)"'
```

The exact JSON field for "this output is mirroring X" varies by sway version;
the reliable signal is visual: both Dells should be displaying the laptop's
content. Don't block on a specific field name.

- [ ] **Step 4: Run the candidate "clear mirror" command and verify**

```bash
swaymsg 'output "Dell Inc. DELL U2417H 5K9YD88IAS0L"  pos 0    0'
swaymsg 'output "Dell Inc. DELL U2417H 5K9YD8B7CYZW"  pos 1920 0'
```

Expected (visually): each Dell stops mirroring and shows its own (empty)
workspace background. If either still mirrors, the design needs a different
mechanism (e.g. `output ... enable` or `swaymsg reload` with rewritten
config). In that case, stop and update the spec; do not invent a workaround.

- [ ] **Step 5: Restore the pre-test state**

```bash
swaymsg 'output "Dell Inc. DELL U2417H 5K9YD88IAS0L"  pos 0    0 mirror eDP-1'
swaymsg 'output "Dell Inc. DELL U2417H 5K9YD8B7CYZW" pos 1920 0 mirror eDP-1'
```

Lid can stay open for the rest of the plan; the script will be invoked
manually for the close case in later tasks.

No commit for this task — it's a verification gate, not a code change.

---

### Task 2: Add the lid-event script (chezmoi source)

**Files:**
- Create: `private_dot_config/sway/scripts/executable_lid.sh`

- [ ] **Step 1: Create the scripts directory in the chezmoi source**

```bash
mkdir -p ~/.local/share/chezmoi/private_dot_config/sway/scripts
```

- [ ] **Step 2: Write the script**

Create `~/.local/share/chezmoi/private_dot_config/sway/scripts/executable_lid.sh`
with this exact content (no `.tmpl`, no template guards — the file is
deployed verbatim and no-ops when the office Dells aren't present):

```sh
#!/bin/sh
# Toggle the laptop panel and the office-Dell mirror together on lid events.
# Called by bindswitch in 50-lid.conf.
#   lid.sh open   - re-enable eDP-1; re-mirror the Dells onto it.
#   lid.sh close  - clear the Dell mirror; disable eDP-1. Workspaces migrate
#                   automatically per the workspace preferred-output lists in
#                   40-outputs-work.conf.
# On non-office docks (or no dock), the Dell-targeted swaymsg calls log a
# warning and return success; the eDP-1 toggle still works.

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
    # host workspaces. Setting `pos` without `mirror` clears mirror state
    # (verified in Task 1).
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

- [ ] **Step 3: Static-check the script**

```bash
sh -n ~/.local/share/chezmoi/private_dot_config/sway/scripts/executable_lid.sh && echo OK
```

Expected: prints `OK`. A non-zero exit means a syntax error; fix it before
proceeding.

- [ ] **Step 4: Verify chezmoi will deploy it +x to the right path**

```bash
cd ~/.local/share/chezmoi
chezmoi target-path private_dot_config/sway/scripts/executable_lid.sh
chezmoi diff ~/.config/sway/scripts/lid.sh
```

Expected: target-path prints `/home/ben/.config/sway/scripts/lid.sh`; the diff
shows the file being created with mode `0755` (or `+x`). If the target path
is wrong or the mode lacks +x, the `executable_` prefix is in the wrong place.

- [ ] **Step 5: Commit**

```bash
cd ~/.local/share/chezmoi
git add private_dot_config/sway/scripts/executable_lid.sh
git commit -m 'sway/scripts: lid.sh toggles eDP-1 + office Dell mirror'
```

---

### Task 3: Rewrite 50-lid.conf to invoke the script

**Files:**
- Modify (full rewrite): `private_dot_config/sway/config.d/50-lid.conf`

The current content was committed in `e44c7f2` and contains hard-coded
`output eDP-1 disable|enable` lines. We're replacing it wholesale.

- [ ] **Step 1: Replace the file contents**

Write `~/.local/share/chezmoi/private_dot_config/sway/config.d/50-lid.conf`
with this exact content:

```
# Lid switch: delegate to scripts/lid.sh, which handles both the laptop panel
# and the office-Dell mirror together. See scripts/lid.sh for the logic.
# Non-work machines: the Dell-specific lines inside the script no-op when
# those outputs aren't present, so this file is safe to deploy anywhere.
# --reload makes sway re-fire the binding on `swaymsg reload`, so the state
# converges after a config change. --locked lets it run while a screen locker
# is active.
bindswitch --reload --locked lid:on  exec ~/.config/sway/scripts/lid.sh close
bindswitch --reload --locked lid:off exec ~/.config/sway/scripts/lid.sh open
```

Note: the previous file's `bindswitch ... output eDP-1 disable|enable` lines
are gone; their behaviour is now inside the script.

- [ ] **Step 2: Diff and apply the lid script + this file**

```bash
cd ~/.local/share/chezmoi
chezmoi diff ~/.config/sway/scripts/lid.sh ~/.config/sway/config.d/50-lid.conf
chezmoi apply  ~/.config/sway/scripts/lid.sh ~/.config/sway/config.d/50-lid.conf
```

Expected: the diff shows `lid.sh` being created and `50-lid.conf` being
rewritten; `apply` runs without prompting for 1Password (neither file
references `onepasswordRead`).

- [ ] **Step 3: Verify the deployed files**

```bash
ls -l ~/.config/sway/scripts/lid.sh ~/.config/sway/config.d/50-lid.conf
```

Expected: `lid.sh` is mode `-rwxr-xr-x` (+x); `50-lid.conf` is mode
`-rw-r--r--`.

- [ ] **Step 4: Reload sway and confirm no syntax error**

```bash
swaymsg reload && echo OK
```

Expected: `[{"success": true}]` followed by `OK`. A non-success result means
sway rejected the config; check `journalctl --user -u sway -n 50` or stderr
for the line number, fix the file, and re-run.

- [ ] **Step 5: Confirm the bindswitches are now exec-style**

The visible side-effect is that closing the lid runs the script. To smoke-
test without the script's full behaviour: open the lid (so `eDP-1` is
enabled and the Dells are still in mirror state from Task 1's restore),
then invoke the script manually:

```bash
~/.config/sway/scripts/lid.sh close
swaymsg -t get_outputs | jq -r '.[] | "\(.name) active=\(.active)"'
```

Expected: `eDP-1 active=false`, both Dells `active=true`. (Workspaces will
still be on `eDP-1` because the workspace preferred-output config isn't in
place yet — that's Task 4.) Restore:

```bash
~/.config/sway/scripts/lid.sh open
```

- [ ] **Step 6: Commit**

```bash
cd ~/.local/share/chezmoi
git add private_dot_config/sway/config.d/50-lid.conf
git commit -m 'sway/config.d/50-lid: delegate lid handling to scripts/lid.sh'
```

---

### Task 4: Office output + workspace assignments (work-only template)

**Files:**
- Create: `private_dot_config/sway/config.d/40-outputs-work.conf.tmpl`

- [ ] **Step 1: Write the template**

Create
`~/.local/share/chezmoi/private_dot_config/sway/config.d/40-outputs-work.conf.tmpl`
with this exact content:

```
{{- if eq .machine_role "work" -}}
# Office dock: two identical Dell U2417Hs, pinned by serial because the same
# make+model can't be disambiguated otherwise. When connected and the lid is
# open they mirror the laptop panel; scripts/lid.sh disables the mirror on
# close so each Dell becomes an independent output that can host workspaces.
output "Dell Inc. DELL U2417H 5K9YD88IAS0L" pos 0    0 mirror eDP-1
output "Dell Inc. DELL U2417H 5K9YD8B7CYZW" pos 1920 0 mirror eDP-1

# Workspace placement: first choice eDP-1 (lid open -> all on the laptop, with
# the Dells mirroring); fall back to the appropriate Dell when eDP-1 is
# disabled (lid closed). Sway auto-migrates existing workspaces when an
# earlier preferred output appears or disappears.
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

- [ ] **Step 2: Render the template against the current data and inspect it**

```bash
cd ~/.local/share/chezmoi
chezmoi execute-template < private_dot_config/sway/config.d/40-outputs-work.conf.tmpl
```

Expected on a work box (`chezmoi data | jq -r .machine_role` should print
`work`): the rendered output is the file body without the
`{{- if ... -}}` / `{{- end -}}` wrappers. On a personal box it would render
empty; verify the current machine is work before continuing:

```bash
chezmoi execute-template '{{ .machine_role }}'
```

Expected: `work`. If it prints anything else, stop — this plan is targeted at
the work box.

- [ ] **Step 3: Diff and apply just this file**

```bash
chezmoi diff  ~/.config/sway/config.d/40-outputs-work.conf
chezmoi apply ~/.config/sway/config.d/40-outputs-work.conf
```

Expected: the diff shows the file being created with the rendered content
(no template delimiters); `apply` runs without prompting for 1Password.

- [ ] **Step 4: Reload sway and verify no error**

```bash
swaymsg reload && echo OK
```

Expected: `[{"success": true}]` then `OK`. If sway rejects the config,
inspect with `journalctl --user -u sway -n 50` and fix.

- [ ] **Step 5: Confirm bindswitches re-fired the lid script in the correct state**

With the lid currently open, `bindswitch --reload` for `lid:off` should have
re-run `scripts/lid.sh open`, restoring mirror state on both Dells:

```bash
swaymsg -t get_outputs | jq -r '.[] | "\(.name) active=\(.active) rect=\(.rect.width)x\(.rect.height)"'
```

Expected: all three outputs `active=true`. (Direct mirror confirmation is
visual — both Dells show what the laptop shows.)

- [ ] **Step 6: Commit**

```bash
cd ~/.local/share/chezmoi
git add private_dot_config/sway/config.d/40-outputs-work.conf.tmpl
git commit -m 'sway/config.d/40-outputs-work: office Dell mirror + workspace split'
```

---

### Task 5: Verify lid-open behaviour end-to-end

**Files:** none. Live-system verification.

- [ ] **Step 1: Confirm lid switch state**

```bash
cat /proc/acpi/button/lid/*/state 2>/dev/null || \
  libinput list-devices | grep -A2 -i lid
```

Expected: `state: open`. If anything else, open the lid before proceeding.

- [ ] **Step 2: Confirm all three outputs active and Dells mirroring**

```bash
swaymsg -t get_outputs | jq -r '.[] | "\(.name) active=\(.active) \(.rect.width)x\(.rect.height) @ (\(.rect.x),\(.rect.y))"'
```

Expected: `eDP-1`, `DP-6`, `DP-7` all `active=true`. Dells should be at
`(0,0)` and `(1920,0)`; `eDP-1` should be at `(0,0)` as well (since the
Dells are mirroring it, sway will overlap their positions onto the source —
this is normal and not a layout bug).

- [ ] **Step 3: Confirm visual mirror**

Visual check (no command): both Dells should be showing the same content as
the laptop screen, letterboxed to 1920x1080 (the laptop is 1920x1200). A
moving cursor on `eDP-1` should appear on both Dells simultaneously.

- [ ] **Step 4: Confirm workspaces all live on eDP-1**

```bash
swaymsg -t get_workspaces | jq -r '.[] | "\(.num) -> \(.output)"' | sort -n
```

Expected: every workspace's output is `eDP-1`. If any workspace shows a Dell
as its output, the preferred-output list is being interpreted wrong; double-
check the spelling of `eDP-1` (capital E, lowercase d, capital P, dash, one)
in `40-outputs-work.conf.tmpl`.

No commit for this task.

---

### Task 6: Verify lid-close behaviour

**Files:** none. Live-system verification.

- [ ] **Step 1: Close the lid (or simulate via script)**

Either physically close the lid, or invoke the script directly:

```bash
~/.config/sway/scripts/lid.sh close
```

(Physically closing also exercises the bindswitch wiring; invoking the
script tests the script in isolation. Both should produce the same end
state.)

- [ ] **Step 2: Confirm eDP-1 is off, Dells are independent outputs**

```bash
swaymsg -t get_outputs | jq -r '.[] | "\(.name) active=\(.active) \(.rect.width)x\(.rect.height) @ (\(.rect.x),\(.rect.y))"'
```

Expected: `eDP-1 active=false`; `DP-6 active=true 1920x1080 @ (0,0)`;
`DP-7 active=true 1920x1080 @ (1920,0)`.

- [ ] **Step 3: Confirm workspaces 1-5 are on the left Dell, 6-10 on the right**

```bash
for i in $(seq 1 10); do swaymsg workspace number $i >/dev/null; done
swaymsg -t get_workspaces | jq -r '.[] | "\(.num) -> \(.output)"' | sort -n
```

The `for` loop ensures each workspace exists (sway creates workspaces
lazily); the second command then shows where they live. Expected:

```
1 -> DP-6
2 -> DP-6
3 -> DP-6
4 -> DP-6
5 -> DP-6
6 -> DP-7
7 -> DP-7
8 -> DP-7
9 -> DP-7
10 -> DP-7
```

If a workspace lands on the wrong Dell, check that the serial number in the
workspace line of `40-outputs-work.conf.tmpl` matches the physical screen
(left = `5K9YD88IAS0L`, right = `5K9YD8B7CYZW`). If the user has swapped the
Dells physically since Task 1's hardware capture, update the spec and the
template together.

No commit for this task.

---

### Task 7: Verify lid-open recovery

**Files:** none. Live-system verification.

- [ ] **Step 1: Open the lid (or simulate via script)**

```bash
~/.config/sway/scripts/lid.sh open
```

or physically open the lid.

- [ ] **Step 2: Confirm we are back in the lid-open state**

```bash
swaymsg -t get_outputs   | jq -r '.[] | "\(.name) active=\(.active)"'
swaymsg -t get_workspaces | jq -r '.[] | "\(.num) -> \(.output)"' | sort -n
```

Expected: all three outputs `active=true`; every workspace back on `eDP-1`.
The Dells should be visually mirroring `eDP-1` again.

- [ ] **Step 3: Cycle once more (close → open) to confirm idempotency**

```bash
~/.config/sway/scripts/lid.sh close
sleep 1
~/.config/sway/scripts/lid.sh open
swaymsg -t get_outputs | jq -r '.[] | "\(.name) active=\(.active)"'
```

Expected: same final state — all outputs active, Dells mirroring. If `eDP-1`
doesn't come back, or a Dell stays in non-mirror mode after `open`, there's
a state-leak; iterate on the script.

No commit for this task.

---

### Task 8: Push to upstream

**Files:** none. Git operation.

- [ ] **Step 1: Review the commits about to be pushed**

```bash
cd ~/.local/share/chezmoi
git log --oneline origin/main..HEAD
```

Expected: three commits from this plan (Tasks 2, 3, 4), plus the design
commit (`64b8db4`) and lid commit (`e44c7f2`) if they haven't been pushed
yet — adjust as appropriate.

- [ ] **Step 2: Ensure the github SSH key is loaded**

```bash
ssh-add -l | grep -q dev@ben.periton.co.uk && echo OK
```

Expected: `OK`. If absent, the user must run `! ssh-add ~/.ssh/id_github` in
the prompt (the `!` prefix runs the command in this session so the
passphrase prompt is visible) before the push will succeed.

- [ ] **Step 3: Push**

```bash
cd ~/.local/share/chezmoi
git push
```

Expected: `main -> main` line in the output, no error.

---

## Self-review notes

- **Spec coverage:** all six file-layout items in the spec map to tasks
  (Tasks 2/3/4); the behaviour matrix is verified in Tasks 5/6/7; the
  caveats (mirror clear, letterboxing, missing outputs) are referenced
  inline in the relevant tasks.
- **No placeholders:** every `swaymsg`, `jq`, and `git` invocation is
  written out; no "TBD" or "implement later".
- **Name consistency:** `LEFT`/`RIGHT` shell vars, `5K9YD88IAS0L` vs
  `5K9YD8B7CYZW`, and `~/.config/sway/scripts/lid.sh` are used identically
  across the script, the conf file, and the verification commands.
- **Hardware capture is a gate, not an assumption:** Task 1 Step 1 re-reads
  the serials live; if they've changed (Dells swapped, replaced) the plan
  stops and points back at the spec.
