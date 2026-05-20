# Sway office-dock layout Implementation Plan

> **Revised 2026-05-20.** Task 1 of the original plan (smoke-test the
> `output ... mirror` directive) failed: sway 1.11 returns
> `Invalid output subcommand: mirror` — the keyword does not exist in sway
> core. The spec was revised in the same session to drop the mirror
> requirement; workspaces 1-5/6-10 are now pinned to the Dells regardless of
> lid state, with `eDP-1` as a fallback. The lid-event handling stays as the
> pre-existing `50-lid.conf` from commit e44c7f2 (no new script, no rewrite).
> The plan below is the revised, simplified plan that matches the revised
> spec. The original task list is preserved in the git history of this file
> (pre-revision: commit fbb2233).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the work laptop is docked to its two office Dell U2417Hs, pin workspaces 1-5 to the left Dell and 6-10 to the right Dell. Undocked, fall back to the laptop panel. The existing `50-lid.conf` already disables `eDP-1` on lid close, so the lid behaviour is unchanged.

**Architecture:** One new chezmoi-managed file: `40-outputs-work.conf.tmpl`, work-role-gated. It contains the two Dell `output` blocks (positioning only, no `mirror`) and the ten `workspace N output ... eDP-1` lines that drive the placement. Sway's "first-available preferred output" rule does the migration when the Dells appear or disappear.

**Tech Stack:** sway 1.11 (Wayland compositor) with `swaymsg`, chezmoi (Go text/template). Validation: `chezmoi execute-template` + `chezmoi diff`; deployment is targeted `chezmoi apply <path>` (no 1Password prompts since this file doesn't reference `onepasswordRead`).

Spec: `docs/superpowers/specs/2026-05-20-sway-office-dock-design.md`.

All commands run from the chezmoi source directory unless noted:
`cd ~/.local/share/chezmoi`.

---

### Task 1: Office output + workspace assignments (work-only template)

**Files:**
- Create: `private_dot_config/sway/config.d/40-outputs-work.conf.tmpl`

- [ ] **Step 1: Write the template**

Create
`~/.local/share/chezmoi/private_dot_config/sway/config.d/40-outputs-work.conf.tmpl`
with this exact content:

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

- [ ] **Step 2: Verify the template renders correctly for this machine**

```bash
cd ~/.local/share/chezmoi
chezmoi execute-template '{{ .machine_role }}'
chezmoi execute-template < private_dot_config/sway/config.d/40-outputs-work.conf.tmpl
```

Expected: first command prints `work`. Second command prints the file body
without `{{- ... -}}` delimiters: two `output ... pos ...` lines and ten
`workspace N output ...` lines. If the second command prints empty, the
machine is not flagged as `work` — stop and reconcile with the user.

- [ ] **Step 3: Diff and apply just this file**

```bash
chezmoi diff  ~/.config/sway/config.d/40-outputs-work.conf
chezmoi apply ~/.config/sway/config.d/40-outputs-work.conf
```

Expected: the diff shows the file being created with the rendered content;
`apply` runs without prompting for 1Password (this file has no
`onepasswordRead`).

- [ ] **Step 4: Reload sway and verify no error**

```bash
swaymsg reload && echo OK
```

Expected: `[{"success": true}]` then `OK`. If sway rejects the config,
inspect with `journalctl --user -u sway -n 50` and fix.

- [ ] **Step 5: Commit**

```bash
cd ~/.local/share/chezmoi
git add private_dot_config/sway/config.d/40-outputs-work.conf.tmpl
git commit -m 'sway/config.d/40-outputs-work: pin office Dell positions + workspace split'
```

---

### Task 2: Verify workspace placement (live system)

**Files:** none. Verification only.

- [ ] **Step 1: Capture current lid state and outputs**

```bash
swaymsg -t get_outputs | jq -r '.[] | "\(.name) active=\(.active) pos=(\(.rect.x),\(.rect.y))"'
```

Expected (lid open, both Dells connected):
- `DP-6 active=true pos=(0,0)`
- `DP-7 active=true pos=(1920,0)`
- `eDP-1 active=true pos=(<something>,0)`

If `eDP-1 active=false`, the lid is closed: that's a valid test state too, the
workspaces should still pin to the Dells. Proceed.

- [ ] **Step 2: Force all ten workspaces to exist, then list their outputs**

```bash
for i in $(seq 1 10); do swaymsg workspace number $i >/dev/null; done
swaymsg -t get_workspaces | jq -r '.[] | "\(.num) -> \(.output)"' | sort -n
```

Expected:
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

If a workspace lands on a different output, check that the serial in
`40-outputs-work.conf.tmpl` matches the physical screen
(left = `5K9YD88IAS0L`, right = `5K9YD8B7CYZW`). If serials need to be
flipped, update the template, re-apply, re-reload.

- [ ] **Step 3: Close the lid and re-verify**

Physically close the lid, then:

```bash
swaymsg -t get_outputs | jq -r '.[] | "\(.name) active=\(.active)"'
swaymsg -t get_workspaces | jq -r '.[] | "\(.num) -> \(.output)"' | sort -n
```

Expected: `eDP-1 active=false`; workspaces 1-5 still on DP-6, 6-10 still on
DP-7. The lid state should make no difference to workspace placement (this is
the post-revision intent).

- [ ] **Step 4: Reopen the lid and re-verify**

Physically open the lid, then re-run the `get_outputs` + `get_workspaces`
queries from Step 3. Expected: `eDP-1 active=true`; workspaces still split
1-5/6-10 across the Dells, NOT migrated to `eDP-1`.

No commit for this task.

---

### Task 3: Push to upstream

**Files:** none. Git operation.

- [ ] **Step 1: Review the commits about to be pushed**

```bash
cd ~/.local/share/chezmoi
git log --oneline origin/main..HEAD
```

Expected: the Task-1 commit from this plan, plus any pending design/plan
revisions ahead of `origin/main`.

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

Expected: `main -> main`, no error.

---

## Self-review notes

- **Spec coverage:** the revised spec's two design pieces (Dell output
  positions + workspace pinning) are both in Task 1 Step 1. The behaviour
  matrix is exercised in Task 2.
- **No placeholders:** every command is written out; no `<...>` in code
  blocks.
- **Name consistency:** serial `5K9YD88IAS0L` = left = workspaces 1-5;
  serial `5K9YD8B7CYZW` = right = workspaces 6-10. Used identically across
  the template and verification steps.
