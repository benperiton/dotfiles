# Cloudflare WARP on the work machine: design

**Date:** 2026-05-19
**Status:** Approved

## Problem

The work Fedora box needs the Cloudflare WARP client (the Zero Trust /
Cloudflare One agent; package `cloudflare-warp`, CLI `warp-cli`). chezmoi
currently installs nothing for it. The `work` `ROLE_PACKAGES` array in
`run_onchange_before_01-install-packages.sh.tmpl` is empty.

Constraints, from the user:

- The box is **not** in MDM, so there is no managed `mdm.xml` auto-enrollment.
  chezmoi installs the client only; enrollment is done **manually**, connecting
  to the Zero Trust org via **SSO** (browser/IdP).
- No organization/team name is stored in the repo, so no new `onepasswordRead`
  item is introduced (consistent with "not in MDM").

Caveat that shapes the design: Cloudflare officially supports only
Ubuntu/Debian and RHEL/CentOS for the Linux client. Fedora is
community-supported (works in practice, widely confirmed) but not official.
The RPM repo uses a **fixed** baseurl (`https://pkg.cloudflareclient.com/rpm`),
not `$releasever`, so the common Fedora release-mismatch 404 does **not**
apply here.

## Design (Approach B: isolated, warn-and-continue)

All changes are in
`.chezmoiscripts/run_onchange_before_01-install-packages.sh.tmpl`, gated
`{{- if eq .machine_role "work" }}`. Personal and headless-personal machines
get nothing. A headless work box would also install it, which is acceptable
since WARP is a CLI/daemon and not GUI-dependent, so there is no
`machine_type` gate.

Because Fedora is not officially supported by Cloudflare, the package is **not**
added to the `ROLE_PACKAGES` array. That array feeds the single
`sudo dnf install -y "${MISSING[@]}"` batch under `set -euo pipefail`, where a
future Fedora-incompatible WARP build would abort the entire package pass.
Instead it is installed in its own guarded subshell, exactly matching the
existing "optional internet-fetched tools" pattern lower in the same file
(Claude Code / Devbox / jj): a failure warns and continues, and never aborts
provisioning of the rest of the machine.

### Repo + install as one self-contained work-only unit

Placed near the optional-tools section (after the `jj` block), repo definition
and install co-located so the unofficial repo is only added on work boxes and
only when the install is actually attempted, and the whole unit is skippable:

1. **Repo add**, guarded by `if ! dnf repolist | grep -q cloudflare-warp`:
   - `sudo rpm --import https://pkg.cloudflareclient.com/pubkey.gpg`
   - write `/etc/yum.repos.d/cloudflare-warp.repo` via the same
     `echo -e ... | sudo tee ... > /dev/null` idiom used by the Edge / Chrome /
     VS Code repo blocks, with:
     - `[cloudflare-warp-stable]`
     - `name=cloudflare-warp`
     - `baseurl=https://pkg.cloudflareclient.com/rpm`
     - `enabled=1`
     - `type=rpm`
     - `gpgcheck=1`
     - `gpgkey=https://pkg.cloudflareclient.com/pubkey.gpg`
2. **Install**, guarded by `if ! rpm -q cloudflare-warp &>/dev/null`, in a
   subshell mirroring the jj/Devbox pattern:
   ```
   if ! ( set -eo pipefail; sudo dnf install -y cloudflare-warp ); then
       echo "WARNING: cloudflare-warp install failed (Fedora unsupported or network?); skipping" >&2
   fi
   ```

Style note: the existing sibling WARNING lines in this file use an em-dash
(e.g. `failed — skipping`). The new line deliberately uses a plain hyphen /
semicolon to comply with the user's global no-dash rule. This minor
inconsistency with the surrounding lines is intentional; an implementer or
reviewer should not "fix" it back to an em-dash.

Idempotent: the `dnf repolist | grep -q` guard (repo conventions) and the
`rpm -q` guard (package conventions) mean re-applies are no-ops once installed.
`run_onchange_` re-runs only when the rendered script content changes.

### Out of repo scope: documented manual steps

Recorded here, not scripted (no org name in the repo, SSO is interactive):

- One-time enrollment after install:
  - `warp-cli teams-enroll <team-name>` (Zero Trust SSO; opens the browser to
    Cloudflare One or the IdP), then `warp-cli connect`.
  - `<team-name>` is the org slug from `<team-name>.cloudflareaccess.com`.
- The `cloudflare-warp` package ships and enables `warp-svc.service` itself;
  no systemd unit work in chezmoi.
- WireGuard coexistence: the box already provisions `wireguard-tools` and
  `run_once_before_07-setup-wireguard.sh.tmpl`. WARP brings its own
  `CloudflareWARP` interface; do not run a manual WireGuard tunnel and WARP
  over overlapping routes simultaneously. Documentation note only.

## Out of scope

- No `mdm.xml` / managed deployment (box is not in MDM).
- No organization/team name or any secret stored in the repo; no new
  `onepasswordRead`.
- No automatic enrollment, connection, or `warp-svc` enablement by chezmoi.
- No change to the `ROLE_PACKAGES` array, the main package batch, or any other
  script.

## Verification

`chezmoi execute-template` renders of
`run_onchange_before_01-install-packages.sh.tmpl` for **work-laptop** and
**personal-laptop**, asserting:

- The work render contains the `cloudflare-warp.repo` write, the
  `https://pkg.cloudflareclient.com/rpm` baseurl, the `pubkey.gpg` import, and
  the guarded `sudo dnf install -y cloudflare-warp` subshell with its
  warn-and-continue `||` branch.
- The personal render contains **none** of the above (the string
  `cloudflare-warp` appears nowhere).
- The rendered work script is valid bash (`bash -n` on the render).
- `chezmoi diff` shows only the intended change to script `01`.
