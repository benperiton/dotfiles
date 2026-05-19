# Browsers to distro packages — design

**Date:** 2026-05-19
**Status:** Approved

## Problem

Google Chrome and Microsoft Edge are installed as Flatpaks by
`run_onchange_before_08-setup-gui-apps.sh.tmpl`:

- `com.google.Chrome` in `COMMON_FLATPAKS` (every GUI machine, personal + work)
- `com.microsoft.Edge` in the `work` `ROLE_FLATPAKS` (work GUI machines only)

We want both as native distro (dnf) packages instead, following the pattern
VS Code already uses (`code` via the Microsoft dnf repo in
`run_onchange_before_01-install-packages.sh.tmpl`), while preserving the
existing work/personal split. Separately, Firefox is currently not declared
anywhere; the Sway-based minimal install does not guarantee it, so it should
be installed explicitly on all GUI machines.

The package-naming concern (`microsoft-edge` vs `microsoft-edge-stable`) is
addressed below: Microsoft's Edge repo ships real packages
`microsoft-edge-stable` / `-beta` / `-dev`; `microsoft-edge` is only a virtual
provide of `microsoft-edge-stable`. Referencing the bare name would break the
`rpm -q` idempotency check in script `01`, so the config references exactly
`microsoft-edge-stable` and never `microsoft-edge`.

## Design

### `run_onchange_before_01-install-packages.sh.tmpl`

**Package lists** — inside the existing `{{ ne .machine_type "headless" }}`
GUI block, extend `GUI_PACKAGES`:

```
GUI_PACKAGES=(
    … existing …
    code
    firefox                  # Fedora main repo — no extra repo needed
    google-chrome-stable     # Google repo — all GUI machines
{{- if eq .machine_role "work" }}
    microsoft-edge-stable    # Microsoft Edge repo — work only
{{- end }}
)
```

- `firefox` and `google-chrome-stable` land on every GUI machine (personal +
  work), like `code`.
- `microsoft-edge-stable` is nested behind the work-role conditional so it
  stays work-only.
- All three are real RPM names, so the existing `rpm -q "$pkg"` missing-loop
  stays idempotent. The bare virtual name `microsoft-edge` is never used.

**Repo setup** — in the same GUI block that already configures the RPM Fusion
and VS Code repos, mirroring that exact pattern:

- **Google Chrome** (all GUI machines):
  `if ! dnf repolist | grep -q google-chrome` →
  `sudo rpm --import https://dl.google.com/linux/linux_signing_key.pub`, then
  write `/etc/yum.repos.d/google-chrome.repo` with baseurl
  `https://dl.google.com/linux/chrome/rpm/stable/x86_64`, `enabled=1`,
  `gpgcheck=1`, `gpgkey=https://dl.google.com/linux/linux_signing_key.pub`.
- **Microsoft Edge** (wrapped in `{{ if eq .machine_role "work" }}`):
  `if ! dnf repolist | grep -q microsoft-edge` →
  `sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc` (same
  key VS Code already trusts; `rpm --import` is idempotent), then write
  `/etc/yum.repos.d/microsoft-edge.repo` with baseurl
  `https://packages.microsoft.com/yumrepos/edge`, `enabled=1`, `gpgcheck=1`,
  `gpgkey=https://packages.microsoft.com/keys/microsoft.asc`.

These repo blocks run under the script's `set -euo pipefail`, exactly like the
existing RPM Fusion / VS Code repo blocks. A browser repo failure *should*
surface — these are not in the "optional, non-fatal curl installer" category
lower in the file.

The existing rationale comment above `code` in `GUI_PACKAGES` is extended to
state that Chrome/Edge/Firefox are deliberately dnf, not Flatpak.

### `run_onchange_before_08-setup-gui-apps.sh.tmpl`

- Remove `com.google.Chrome` from `COMMON_FLATPAKS`.
- Remove `com.microsoft.Edge` from the `work` `ROLE_FLATPAKS`.
- Update the `NOTE:` comment block (currently VS-Code-only rationale) to also
  cover Chrome/Edge/Firefox, pointing at script `01`.
- No Flatpak uninstall logic. Existing Flatpaks are removed manually by the
  user. Profile data does not migrate: Flatpak Chrome stores it under
  `~/.var/app/com.google.Chrome/`, distro Chrome uses `~/.config/google-chrome/`.

Net effect by machine:

| machine | change |
| --- | --- |
| personal GUI | Chrome + Firefox now via dnf; Chrome Flatpak no longer installed |
| work GUI | Chrome + Firefox + Edge now via dnf; Chrome & Edge Flatpaks no longer installed |
| any headless | unchanged (no browsers; both scripts still no-op) |

## Out of scope

- No automatic removal of the existing `com.google.Chrome` /
  `com.microsoft.Edge` Flatpaks — done manually by the user.
- Edge channel is **stable** (`microsoft-edge-stable`); beta/dev not installed.
- The `2026-05-18-per-role-gui-flatpaks` design/plan docs still describe
  Chrome/Edge as Flatpaks. They are historical records and are not rewritten;
  this spec supersedes the Chrome/Edge placement decided there.
- No change to any other Flatpak, dnf package, or the VS Code arrangement.

## Verification

`chezmoi execute-template` renders of both scripts for **personal-desktop**
and **work-desktop**, asserting:

- Chrome (`google-chrome-stable`) and `firefox` present in the script `01`
  render for both roles.
- `microsoft-edge-stable` present in the work render only; absent in personal.
- The bare string `microsoft-edge` (without `-stable`) appears nowhere in the
  rendered script `01`.
- `com.google.Chrome` and `com.microsoft.Edge` absent from the script `08`
  render for both roles.
- Script `08` still renders a valid Flathub remote-add + install loop for the
  remaining apps.
