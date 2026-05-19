# Browsers to Distro Packages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install Firefox on all GUI machines, Google Chrome on personal GUI machines, and Microsoft Edge on work GUI machines via dnf (vendor repos), and remove the Chrome/Edge Flatpaks. (Chrome is personal-only — Edge is Chromium-based and covers the work machine.)

**Architecture:** Extend `GUI_PACKAGES` in `run_onchange_before_01-install-packages.sh.tmpl` with `firefox` (all GUI) plus a personal/work branch (`google-chrome-stable` personal, `microsoft-edge-stable` work); add Google Chrome (personal) and Microsoft Edge (work) dnf `.repo` blocks in a matching personal/work branch alongside the existing RPM Fusion / VS Code repo blocks. Drop `com.google.Chrome` / `com.microsoft.Edge` from `run_onchange_before_08-setup-gui-apps.sh.tmpl`. No new abstractions; reuses the existing `rpm -q` idempotency loop and the template's `machine_type` / `machine_role` conditionals (the same personal/work branch pattern already used for `ROLE_FLATPAKS` and `ROLE_PACKAGES`).

**Tech Stack:** chezmoi v2.70.0 (Go text/template), bash, dnf, Fedora.

**Spec:** `docs/superpowers/specs/2026-05-19-browsers-to-distro-packages-design.md`

**Branch:** `browsers-to-distro-packages` — created off `main` in Setup below (the spec doc is already committed on `main` at `5876e55`).

---

## Verification approach

Dotfiles/template repo — no unit tests. Neither `01-install-packages.sh.tmpl` nor `08-setup-gui-apps.sh.tmpl` contains `onepasswordRead`, so `chezmoi execute-template` on them is non-interactive and safe (no 1Password prompt).

Per-task verification uses three layers, matching `docs/superpowers/plans/2026-05-18-per-role-gui-flatpaks.md`:

1. **Static `rg -F` assertions** on the template source — verify the literal lines and the work-gated `{{- if eq .machine_role "work" }}` blocks exist.
2. **A real `chezmoi execute-template` render for the current (personal) role** + `bash -n` on the output — verifies the personal path renders to valid bash and that work-only content (`microsoft-edge-stable`, the Edge repo block) is correctly *absent* on personal.
3. **Work-role behavior** cannot be rendered on this personal machine — `promptChoiceOnce` returns the persisted `personal` and `--promptChoice machine_role=work` is ignored (established in the prior plan). It is verified by the static source assertions here plus a manual `chezmoi apply` on the actual work machine at rollout (Task 3).

---

## Setup: create the feature branch

- [ ] **Step 1: Branch off `main`**

```bash
cd ~/.local/share/chezmoi
git switch -c browsers-to-distro-packages
git branch --show-current
```

Expected: prints `browsers-to-distro-packages`. (HEAD already includes the spec commit `5876e55`.)

---

### Task 1: Script `01` — add browsers to `GUI_PACKAGES` + add Chrome/Edge dnf repos

**Files:**
- Modify: `.chezmoiscripts/run_onchange_before_01-install-packages.sh.tmpl` (the `GUI_PACKAGES` array, currently lines 23-43; and the GUI repo-setup block, currently lines 46-64)

This is one coherent commit: a package without its repo would fail at `dnf install`, and a repo without its package would install nothing — they ship together.

- [ ] **Step 1: Confirm the starting state (the "failing test")**

```bash
cd ~/.local/share/chezmoi
chezmoi execute-template < .chezmoiscripts/run_onchange_before_01-install-packages.sh.tmpl > /tmp/01rendered.sh
rg -F -e 'firefox' -e 'google-chrome-stable' -e 'microsoft-edge-stable' /tmp/01rendered.sh || echo "browsers absent — expected before edit"
rg -F 'google-chrome.repo' /tmp/01rendered.sh || echo "chrome repo absent — expected before edit"
```

Expected: the `rg` finds nothing; both fallback messages print. This confirms the change is not yet present.

- [ ] **Step 2: Edit the `GUI_PACKAGES` comment + tail**

In `.chezmoiscripts/run_onchange_before_01-install-packages.sh.tmpl`, replace this exact block:

```
    # VS Code: installed via the Microsoft dnf repo (configured below), NOT as a
    # Flatpak. The Flatpak build is sandboxed and breaks the integrated terminal,
    # host toolchain/Docker access, and many extensions. Kept in GUI_PACKAGES
    # (role-agnostic) so it lands on both personal and work GUI machines.
    # See run_onchange_before_08-setup-gui-apps.sh.tmpl.
    code
)
```

with:

```
    # Browsers + VS Code: installed via dnf (Microsoft/Google repos configured
    # below), NOT as Flatpaks. Flatpak builds are sandboxed and break host
    # integration — VS Code: the integrated terminal, host toolchain/Docker,
    # and many extensions; browsers: native messaging and host file access.
    # firefox is role-agnostic (all GUI machines); google-chrome-stable is
    # personal-only; microsoft-edge-stable is work-only (Chromium-based, so it
    # replaces Chrome on work). The matching Flatpaks are removed in
    # run_onchange_before_08-setup-gui-apps.sh.tmpl.
    code
    firefox
{{- if eq .machine_role "personal" }}
    google-chrome-stable
{{- else if eq .machine_role "work" }}
    microsoft-edge-stable
{{- end }}
)
```

(The `{{- if eq .machine_role "personal" }} … {{- else if eq .machine_role "work" }} … {{- end }}` nested inside a bash array is the same pattern already proven to render to valid bash in `08-setup-gui-apps.sh.tmpl`.)

- [ ] **Step 3: Edit the repo-setup block — add Chrome + work-gated Edge repos**

In the same file, replace this exact block:

```
fi
{{- end }}

# Docker repo (needed for docker-ce packages)
```

with:

```
fi
{{- if eq .machine_role "personal" }}

# Google Chrome repo (personal machines only)
if ! dnf repolist | grep -q google-chrome; then
    sudo rpm --import https://dl.google.com/linux/linux_signing_key.pub
    echo -e "[google-chrome]\nname=google-chrome\nbaseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64\nenabled=1\ngpgcheck=1\ngpgkey=https://dl.google.com/linux/linux_signing_key.pub" | sudo tee /etc/yum.repos.d/google-chrome.repo > /dev/null
fi
{{- else if eq .machine_role "work" }}

# Microsoft Edge repo (work machines only)
if ! dnf repolist | grep -q microsoft-edge; then
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    echo -e "[microsoft-edge]\nname=microsoft-edge\nbaseurl=https://packages.microsoft.com/yumrepos/edge\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/microsoft-edge.repo > /dev/null
fi
{{- end }}
{{- end }}

# Docker repo (needed for docker-ce packages)
```

The first `{{- end }}` closes the personal/work `if/else if` for the browser repos; the second `{{- end }}` closes the original `{{- if ne .machine_type "headless" }}` GUI repo block. The Microsoft GPG key is the same one the VS Code block already imports; `rpm --import` is idempotent, so importing it again in the Edge block is harmless and keeps the block self-contained.

- [ ] **Step 4: Static source assertions**

```bash
cd ~/.local/share/chezmoi
f=.chezmoiscripts/run_onchange_before_01-install-packages.sh.tmpl
rg -F 'firefox' "$f"
rg -F 'google-chrome-stable' "$f"
rg -F 'microsoft-edge-stable' "$f"
rg -cF '{{- if eq .machine_role "personal" }}' "$f"
rg -cF '{{- else if eq .machine_role "work" }}' "$f"
rg -F '/etc/yum.repos.d/google-chrome.repo' "$f"
rg -F '/etc/yum.repos.d/microsoft-edge.repo' "$f"
rg -n -e '^[[:space:]]*microsoft-edge[[:space:]]*$' "$f" && echo "BARE microsoft-edge PACKAGE LINE — FAIL" || echo "no bare microsoft-edge package line — OK"
```

(The bare-package check uses a line-anchored regex — `^\s*microsoft-edge\s*$` — not a fixed-string substring. The substring form gives a false positive because the `echo -e` repo definition legitimately contains the literal text `name=microsoft-edge\n`. Only a line that is *nothing but* `microsoft-edge` would be a bare package entry that breaks the `rpm -q` idempotency check, and that is what this asserts is absent.)

Expected: `firefox`, `google-chrome-stable`, `microsoft-edge-stable`, and both repo-file paths each print their matching line(s); the two `rg -cF` counts each print `3` — the personal/work branch now appears in three places: the pre-existing `ROLE_PACKAGES` block (unchanged), plus the two added by this task (the `GUI_PACKAGES` array and the repo-setup block); the last line prints `no bare microsoft-edge package line — OK` (`microsoft-edge-stable` is the only package entry; every other `microsoft-edge` occurrence is the repo id `[microsoft-edge]`, `name=microsoft-edge`, `grep -q microsoft-edge`, or `microsoft-edge.repo`).

- [ ] **Step 5: Render for the current (personal) role + syntax check**

```bash
cd ~/.local/share/chezmoi
rm -f /tmp/01rendered.sh
chezmoi execute-template < .chezmoiscripts/run_onchange_before_01-install-packages.sh.tmpl > /tmp/01rendered.sh
bash -n /tmp/01rendered.sh && echo "bash -n OK"
rg -n -e '^[[:space:]]*(firefox|google-chrome-stable)[[:space:]]*$' /tmp/01rendered.sh
rg -qF 'dl.google.com/linux/chrome/rpm/stable' /tmp/01rendered.sh && echo "chrome repo present on personal — OK" || echo "CHROME REPO MISSING ON PERSONAL — FAIL"
rg -n -e '^[[:space:]]*microsoft-edge-stable[[:space:]]*$' /tmp/01rendered.sh && echo "EDGE PACKAGE ON PERSONAL — FAIL" || echo "edge package absent on personal — OK"
rg -qF 'packages.microsoft.com/yumrepos/edge' /tmp/01rendered.sh && echo "EDGE REPO ON PERSONAL — FAIL" || echo "edge repo block absent on personal — OK"
```

(Package-entry checks are line-anchored — `^\s*<pkg>\s*$` — not substring greps, because the unconditional explanatory comment above `code` legitimately names `google-chrome-stable` and `microsoft-edge-stable`; a substring grep would match the comment on every role. Repo presence/absence is tested via each vendor's unique baseurl — `dl.google.com/linux/chrome/rpm/stable` for Chrome, `packages.microsoft.com/yumrepos/edge` for Edge — which appear only in the role-gated repo blocks, never in comments. Each check is a self-contained `&& … || …` so one failure can't break the chain.)

Expected: `bash -n OK`; the line-anchored grep lists exactly `firefox` and `google-chrome-stable` as package entries; `chrome repo present on personal — OK`; `edge package absent on personal — OK`; `edge repo block absent on personal — OK`. (The work-gated `microsoft-edge-stable` package entry and Edge repo block are verified present in source by Step 4 and exercised on the work machine in Task 3.)

- [ ] **Step 6: Commit**

```bash
cd ~/.local/share/chezmoi
git add .chezmoiscripts/run_onchange_before_01-install-packages.sh.tmpl
git commit -m "feat: install firefox/chrome via dnf (all GUI), edge via dnf (work)"
```

---

### Task 2: Script `08` — drop Chrome/Edge Flatpaks + update the NOTE

**Files:**
- Modify: `.chezmoiscripts/run_onchange_before_08-setup-gui-apps.sh.tmpl` (the `NOTE:` comment lines 13-16, the `com.google.Chrome` entry in `COMMON_FLATPAKS`, the `com.microsoft.Edge` entry in the work `ROLE_FLATPAKS`)

- [ ] **Step 1: Confirm the starting state (the "failing test")**

```bash
cd ~/.local/share/chezmoi
chezmoi execute-template < .chezmoiscripts/run_onchange_before_08-setup-gui-apps.sh.tmpl > /tmp/08rendered.sh
rg -cF 'com.google.Chrome' /tmp/08rendered.sh
```

Expected: prints `1` (Chrome Flatpak still present in the personal render — confirms the change is not yet made).

- [ ] **Step 2: Replace the NOTE comment**

In `.chezmoiscripts/run_onchange_before_08-setup-gui-apps.sh.tmpl`, replace this exact block:

```
# NOTE: VS Code is intentionally NOT a Flatpak here. It is installed via the
# Microsoft dnf repo in run_onchange_before_01-install-packages.sh.tmpl
# (GUI_PACKAGES) because the Flatpak build is sandboxed and degrades the
# integrated terminal, host toolchains/Docker, and many extensions.
```

with:

```
# NOTE: Web browsers (Firefox, Google Chrome, Microsoft Edge) and VS Code are
# intentionally NOT Flatpaks here. They are installed via dnf in
# run_onchange_before_01-install-packages.sh.tmpl (GUI_PACKAGES): firefox and
# code (VS Code) on all GUI machines; google-chrome-stable on personal machines
# only; microsoft-edge-stable on work machines only (Chromium-based, so it
# replaces Chrome on work). Flatpak builds are sandboxed and degrade host
# integration (VS Code: integrated terminal, host toolchains/Docker,
# extensions; browsers: native messaging, host file access).
```

- [ ] **Step 3: Remove `com.google.Chrome` from `COMMON_FLATPAKS`**

Delete exactly this line (the first entry of the `COMMON_FLATPAKS=(` array):

```
    com.google.Chrome
```

`COMMON_FLATPAKS` must then start:

```
COMMON_FLATPAKS=(
    org.gimp.GIMP
    org.inkscape.Inkscape
```

- [ ] **Step 4: Remove `com.microsoft.Edge` from the work `ROLE_FLATPAKS`**

Delete exactly this line from the `{{- else if eq .machine_role "work" }}` branch:

```
    com.microsoft.Edge
```

The work branch must then read exactly:

```
{{- else if eq .machine_role "work" }}
ROLE_FLATPAKS=(
    io.dbeaver.DBeaverCommunity
)
{{- end }}
```

- [ ] **Step 5: Static source assertions**

```bash
cd ~/.local/share/chezmoi
f=.chezmoiscripts/run_onchange_before_08-setup-gui-apps.sh.tmpl
rg -F 'com.google.Chrome' "$f" && echo "CHROME FLATPAK STILL PRESENT — FAIL" || echo "chrome flatpak gone — OK"
rg -F 'com.microsoft.Edge' "$f" && echo "EDGE FLATPAK STILL PRESENT — FAIL" || echo "edge flatpak gone — OK"
rg -F 'io.dbeaver.DBeaverCommunity' "$f"
rg -F 'md.obsidian.Obsidian' "$f"
rg -F 'Web browsers (Firefox, Google Chrome, Microsoft Edge)' "$f"
```

Expected: `chrome flatpak gone — OK`; `edge flatpak gone — OK`; DBeaver and Obsidian still present (proves only the two browser lines were removed, the work branch and common list are otherwise intact); the new NOTE line prints.

- [ ] **Step 6: Render for the current (personal) role + syntax check**

```bash
cd ~/.local/share/chezmoi
chezmoi execute-template < .chezmoiscripts/run_onchange_before_08-setup-gui-apps.sh.tmpl > /tmp/08rendered.sh
bash -n /tmp/08rendered.sh && echo "bash -n OK"
rg -F -e 'com.google.Chrome' -e 'com.microsoft.Edge' /tmp/08rendered.sh && echo "BROWSER FLATPAK IN RENDER — FAIL" || echo "no browser flatpaks in render — OK"
rg -F -e 'net.cozic.joplin_desktop' -e 'org.gimp.GIMP' /tmp/08rendered.sh
```

Expected: `bash -n OK`; `no browser flatpaks in render — OK`; the personal-role apps (`joplin_desktop`) and a common app (`org.gimp.GIMP`) still present — proves the rest of the script is untouched and still renders a valid install loop.

- [ ] **Step 7: Commit**

```bash
cd ~/.local/share/chezmoi
git add .chezmoiscripts/run_onchange_before_08-setup-gui-apps.sh.tmpl
git commit -m "refactor: drop chrome/edge flatpaks (now installed via dnf)"
```

---

### Task 3: Rollout verification (MANUAL — user, per machine) + finish branch

No prerequisites beyond network access to `dl.google.com` / `packages.microsoft.com`. The existing `com.google.Chrome` / `com.microsoft.Edge` Flatpaks are intentionally left for the user to remove manually (profile data does not migrate: Flatpak `~/.var/app/com.google.Chrome/` vs distro `~/.config/google-chrome/`).

- [ ] **Step 1: Personal machine (this machine)**

```bash
cd ~/.local/share/chezmoi
chezmoi apply --verbose
rpm -q firefox google-chrome-stable
rpm -q microsoft-edge-stable && echo "EDGE ON PERSONAL — FAIL" || echo "edge absent on personal — OK"
ls /etc/yum.repos.d/google-chrome.repo
```

Expected: `firefox` and `google-chrome-stable` report installed versions; `edge absent on personal — OK`; the Chrome repo file exists. (Re-running `chezmoi apply` a second time should be a no-op for these — the `rpm -q` loop and `dnf repolist | grep -q` guards make it idempotent.)

- [ ] **Step 2: Work machine (whenever next on it)**

```bash
cd ~/.local/share/chezmoi
chezmoi apply --verbose
rpm -q firefox microsoft-edge-stable
rpm -q google-chrome-stable && echo "CHROME ON WORK — FAIL" || echo "chrome absent on work — OK"
ls /etc/yum.repos.d/microsoft-edge.repo
ls /etc/yum.repos.d/google-chrome.repo 2>/dev/null && echo "CHROME REPO ON WORK — FAIL" || echo "chrome repo absent on work — OK"
flatpak list --columns=application | rg -e 'com.google.Chrome' -e 'com.microsoft.Edge' || echo "browser flatpaks not (re)installed — OK"
```

Expected: `firefox` and `microsoft-edge-stable` installed; `chrome absent on work — OK`; the Edge repo file exists; `chrome repo absent on work — OK`; `browser flatpaks not (re)installed — OK` (any pre-existing browser Flatpaks are left alone but no longer reinstalled — the user removes them manually).

- [ ] **Step 3: Remove the redundant Flatpaks manually (each machine, optional, after migrating bookmarks)**

```bash
flatpak uninstall -y com.google.Chrome
# work machine only, if it was ever installed:
flatpak uninstall -y com.microsoft.Edge
```

- [ ] **Step 4: Finish the branch.** After Step 1 (personal) verifies, invoke the `superpowers:finishing-a-development-branch` skill to merge `browsers-to-distro-packages` into `main`. Step 2 (work) is confirmed opportunistically and is not a merge gate (the work path is statically verified and idempotent).

---

## Notes for the executor

- `chezmoi execute-template` on scripts `01` and `08` is safe — neither contains `onepasswordRead`, so no 1Password prompt.
- The work-role path (`microsoft-edge-stable`, the Edge repo block) **cannot** be rendered on this personal machine; it is verified by static source assertions in Tasks 1–2 and by `chezmoi apply` on the work machine in Task 3, Step 2.
- Do not add automatic `flatpak uninstall` to the scripts — removal is deliberately manual (Task 3, Step 3) so the user can migrate browser profiles first.
- Tasks 1 and 2 are each independently committable and coherent. The branch can be merged after Task 3 Step 1 (personal) passes; Task 3 Step 2 (work) is opportunistic.
- Reference: `docs/superpowers/plans/2026-05-18-per-role-gui-flatpaks.md` for the verification idiom this plan follows.
