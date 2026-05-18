# Per-role GUI Flatpaks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `run_onchange_before_08-setup-gui-apps.sh.tmpl` install a shared Flatpak set on all GUI machines plus a `machine_role`-specific set (personal: Joplin + Syncthing Tray; work: DBeaver + Edge).

**Architecture:** Replace the single flat `FLATPAKS=(...)` array with `COMMON_FLATPAKS` + a `machine_role` branch defining `ROLE_FLATPAKS`, merged into `FLATPAKS`. Mirrors the existing `ROLE_PACKAGES` pattern in `run_onchange_before_01-install-packages.sh.tmpl`. Everything else in the script is untouched.

**Tech Stack:** chezmoi v2.70 (Go text/template), bash, Flatpak/Flathub.

**Spec:** `docs/superpowers/specs/2026-05-18-per-role-gui-flatpaks-design.md`

**Branch:** `per-role-gui-flatpaks` (already created, off `main`).

---

## Verification approach

Dotfiles/template repo — no unit tests. The 08 script has **no `onepasswordRead`**, so rendering it does not call 1Password (safe, non-interactive). Verification per the one task: deterministic `rg` assertions on the source, a real `chezmoi execute-template` render for the current (personal) role, and `bash -n` on the rendered output. The work-role branch cannot be rendered on this personal machine (`promptChoiceOnce` returns the persisted `personal`; `--promptChoice machine_role=work` is ignored — established earlier this session), so it is verified by static assertion here and by `chezmoi apply` on the actual work machine at rollout.

---

### Task 1: Split `FLATPAKS` into common + role branch

**Files:**
- Modify: `.chezmoiscripts/run_onchange_before_08-setup-gui-apps.sh.tmpl` (lines 13-25, the `FLATPAKS=(...)` array)

Current lines 13-25 are exactly:

```
FLATPAKS=(
    com.google.Chrome
    org.gimp.GIMP
    org.inkscape.Inkscape
    com.sublimetext.three
    org.libreoffice.LibreOffice
    org.filezillaproject.Filezilla
    com.usebruno.Bruno
    net.cozic.joplin_desktop
    org.remmina.Remmina
    com.github.tchx84.Flatseal
    io.github.martchus.syncthingtray
)
```

- [ ] **Step 1: Replace exactly that block with**

```
COMMON_FLATPAKS=(
    com.google.Chrome
    org.gimp.GIMP
    org.inkscape.Inkscape
    com.sublimetext.three
    org.libreoffice.LibreOffice
    org.filezillaproject.Filezilla
    com.usebruno.Bruno
    org.remmina.Remmina
    com.github.tchx84.Flatseal
)

{{- if eq .machine_role "personal" }}
ROLE_FLATPAKS=(
    net.cozic.joplin_desktop
    io.github.martchus.syncthingtray
)
{{- else if eq .machine_role "work" }}
ROLE_FLATPAKS=(
    io.dbeaver.DBeaverCommunity
    com.microsoft.Edge
)
{{- end }}

FLATPAKS=( "${COMMON_FLATPAKS[@]}" "${ROLE_FLATPAKS[@]}" )
```

(Leave lines 1-12 and 26-40 — shebang, headless gate, `set -euo pipefail`, Flathub remote-add, the `MISSING` loop, the install call, the closing `{{- end }}` — exactly as they are. This mirrors the `{{- if eq .machine_role "personal" }} … {{- else if eq .machine_role "work" }} … {{- end }}` + merged-array pattern already used for `ROLE_PACKAGES` in `01-install-packages.sh.tmpl`.)

- [ ] **Step 2: Static assertions**

Run:

```bash
cd ~/.local/share/chezmoi
f=.chezmoiscripts/run_onchange_before_08-setup-gui-apps.sh.tmpl
rg -F 'COMMON_FLATPAKS=(' "$f"
rg -F 'FLATPAKS=( "${COMMON_FLATPAKS[@]}" "${ROLE_FLATPAKS[@]}" )' "$f"
rg -F '{{- if eq .machine_role "personal" }}' "$f"
rg -F '{{- else if eq .machine_role "work" }}' "$f"
rg -F 'net.cozic.joplin_desktop' "$f"
rg -F 'io.github.martchus.syncthingtray' "$f"
rg -F 'io.dbeaver.DBeaverCommunity' "$f"
rg -F 'com.microsoft.Edge' "$f"
rg -cF 'com.google.Chrome' "$f"
```

Expected: every `rg -F` prints its matching line; the final `rg -cF` prints `1` (Chrome appears once, in the common list — proves the old flat list is gone and not duplicated).

- [ ] **Step 3: Render for the current (personal) role + syntax check**

Run:

```bash
cd ~/.local/share/chezmoi
chezmoi execute-template < .chezmoiscripts/run_onchange_before_08-setup-gui-apps.sh.tmpl > /tmp/08rendered.sh
bash -n /tmp/08rendered.sh && echo "bash -n OK"
rg -F -e 'net.cozic.joplin_desktop' -e 'io.github.martchus.syncthingtray' /tmp/08rendered.sh
rg -F -e 'io.dbeaver.DBeaverCommunity' -e 'com.microsoft.Edge' /tmp/08rendered.sh && echo "WORK APPS ON PERSONAL — FAIL" || echo "work apps absent on personal — OK"
rg -cF 'com.google.Chrome' /tmp/08rendered.sh
```

Expected: `bash -n OK`; the personal apps (`joplin_desktop`, `syncthingtray`) present in the rendered output; `work apps absent on personal — OK`; final count `1`. (Work-role rendering is verified on the work machine at rollout — see Task 2.)

- [ ] **Step 4: Commit**

```bash
cd ~/.local/share/chezmoi
git add .chezmoiscripts/run_onchange_before_08-setup-gui-apps.sh.tmpl
git commit -m "feat: per-role GUI flatpaks (personal: joplin/syncthing; work: dbeaver/edge)"
```

---

### Task 2: Rollout verification (MANUAL — user, per machine)

No prerequisites: Flatpaks install from Flathub; no secrets, no repos to add beyond the existing Flathub remote-add already in the script.

- [ ] **Step 1: Personal machine**

```bash
cd ~/.local/share/chezmoi && chezmoi apply --verbose
flatpak list --columns=application | rg -e 'joplin' -e 'syncthingtray'   # present
flatpak list --columns=application | rg -e 'DBeaver' -e 'microsoft.Edge' || echo "work apps absent on personal — OK"
```

Expected: Joplin + Syncthing Tray present; DBeaver/Edge absent. (Common apps and the dnf `code` VS Code are unaffected.)

- [ ] **Step 2: Work machine** (whenever next on it; can be combined with the multi-account Task 11)

```bash
cd ~/.local/share/chezmoi && chezmoi apply --verbose
flatpak list --columns=application | rg -e 'DBeaver' -e 'microsoft.Edge'   # present
flatpak list --columns=application | rg -e 'joplin' -e 'syncthingtray' || echo "personal apps absent on work — OK"
```

Expected: DBeaver + Edge present; Joplin/Syncthing Tray absent.

- [ ] **Step 3: Confirm**, then finish the branch (merge to `main`).

---

## Notes for the executor

- `chezmoi execute-template` on this script is safe (no `onepasswordRead`); it will not prompt 1Password.
- Do not modify `01-install-packages.sh.tmpl` — VS Code (`code`, dnf) is deliberately unchanged per the spec.
- Task 1 is the only code change and is independently committable. Task 2 is user-run and not a code gate; the branch can be merged after Step 1 (personal) verifies, with Step 2 (work) confirmed opportunistically.
