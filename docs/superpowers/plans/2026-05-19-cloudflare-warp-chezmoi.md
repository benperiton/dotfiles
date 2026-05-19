# Cloudflare WARP on the work machine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make chezmoi install the Cloudflare WARP client (`cloudflare-warp`) on work machines only, in an isolated warn-and-continue step, with enrollment left manual.

**Architecture:** One additive, work-role-gated block appended to `.chezmoiscripts/run_onchange_before_01-install-packages.sh.tmpl`, after the existing `jj` optional-tools block. It mirrors the file's existing "fragile optional install" pattern (guarded `rpm -q`, subshell with `set -eo pipefail`, `|| echo WARNING ... skipping`) and the existing repo-write idiom (`echo -e ... | sudo tee /etc/yum.repos.d/<name>.repo`). No `ROLE_PACKAGES` change, no enrollment, no secret.

**Tech Stack:** chezmoi (Go text/template over bash), Fedora `dnf`, Cloudflare RPM repo (`pkg.cloudflareclient.com`). Validation is `chezmoi execute-template` renders + `bash -n` + `chezmoi diff` (this repo has no build/test; per its CLAUDE.md, chezmoi itself is the test). `chezmoi apply` is NOT run (needs a 1Password session; out of scope here).

Spec: `docs/superpowers/specs/2026-05-19-cloudflare-warp-chezmoi-design.md`.

---

### Task 1: Work-only Cloudflare WARP install block

**Files:**
- Modify: `.chezmoiscripts/run_onchange_before_01-install-packages.sh.tmpl` (append at end of file, after the final `fi` of the `jj` block, currently the last line)

All commands run from the chezmoi source dir: `cd ~/.local/share/chezmoi`.

- [ ] **Step 1: Confirm the RED baseline (WARP absent in both renders)**

The repo-local "test" is a rendered-script assertion. Confirm WARP is not present yet:

```bash
cd ~/.local/share/chezmoi
(printf '{{ $_ := set . "machine_role" "work" -}}\n'; cat .chezmoiscripts/run_onchange_before_01-install-packages.sh.tmpl) | chezmoi execute-template 2>&1 | grep -c cloudflare-warp
(printf '{{ $_ := set . "machine_role" "personal" -}}\n'; cat .chezmoiscripts/run_onchange_before_01-install-packages.sh.tmpl) | chezmoi execute-template 2>&1 | grep -c cloudflare-warp
```

Expected: `0` for the work render, `0` for the personal render. (This is the failing-test state: the work render SHOULD contain WARP after the change but does not yet.)

- [ ] **Step 2: Append the work-gated WARP block**

Open `.chezmoiscripts/run_onchange_before_01-install-packages.sh.tmpl`. The file currently ends with the `jj` block:

```
    ); then
        echo "WARNING: jj install failed (network/download blocked?) — skipping" >&2
    fi
fi
```

Append the following immediately after that final `fi` (Edit anchor: the last `fi` of the `jj` block). Reproduce the block exactly, including the `{{- ... }}` template delimiters and the leading blank line:

```
{{- if eq .machine_role "work" }}

# Cloudflare WARP (Zero Trust client). Fedora is community-supported, not
# officially supported by Cloudflare, so the package is installed here in its
# own warn-and-continue subshell rather than in the dnf batch: a future
# Fedora-incompatible build (or a restricted network) must not abort the whole
# package pass. The RPM repo uses a fixed path (no $releasever), so the usual
# Fedora release-mismatch 404 does not apply. Enrollment is manual and via SSO
# (warp-cli teams-enroll <team>; warp-cli connect), intentionally not scripted,
# so no org name or secret lives in the repo (the box is not in MDM).
if ! rpm -q cloudflare-warp &>/dev/null; then
    echo "Installing Cloudflare WARP..."
    if ! (
        set -eo pipefail
        if ! dnf repolist | grep -q cloudflare-warp; then
            sudo rpm --import https://pkg.cloudflareclient.com/pubkey.gpg
            echo -e "[cloudflare-warp-stable]\nname=cloudflare-warp\nbaseurl=https://pkg.cloudflareclient.com/rpm\nenabled=1\ntype=rpm\ngpgcheck=1\ngpgkey=https://pkg.cloudflareclient.com/pubkey.gpg" | sudo tee /etc/yum.repos.d/cloudflare-warp.repo > /dev/null
        fi
        sudo dnf install -y cloudflare-warp
    ); then
        echo "WARNING: cloudflare-warp install failed (Fedora unsupported or network?); skipping" >&2
    fi
fi
{{- end }}
```

Notes for the implementer:
- Do NOT add `cloudflare-warp` to the `ROLE_PACKAGES` array or `ALL_PACKAGES`. This block is the only change.
- The new WARNING line uses a plain hyphen/semicolon, NOT the em-dash the sibling WARNING lines use. This is deliberate (user global no-dash rule); do not "correct" it to match the siblings.
- `$releasever`, `<team>`, and `&>/dev/null` are inside bash (a comment / shell), not Go-template actions, so they need no escaping. The only template constructs are `{{- if eq .machine_role "work" }}` and `{{- end }}`.
- End the file with a single trailing newline after `{{- end }}`.

- [ ] **Step 3: Assert GREEN for the work render**

```bash
cd ~/.local/share/chezmoi
(printf '{{ $_ := set . "machine_role" "work" -}}\n'; cat .chezmoiscripts/run_onchange_before_01-install-packages.sh.tmpl) | chezmoi execute-template 2>&1 > /tmp/warp-work-render.sh
grep -q 'baseurl=https://pkg.cloudflareclient.com/rpm' /tmp/warp-work-render.sh && echo "baseurl OK"
grep -q 'sudo rpm --import https://pkg.cloudflareclient.com/pubkey.gpg' /tmp/warp-work-render.sh && echo "gpgkey import OK"
grep -q 'sudo dnf install -y cloudflare-warp' /tmp/warp-work-render.sh && echo "install OK"
grep -q 'WARNING: cloudflare-warp install failed' /tmp/warp-work-render.sh && echo "warn-and-continue OK"
```

Expected: all four lines print (`baseurl OK`, `gpgkey import OK`, `install OK`, `warn-and-continue OK`).

- [ ] **Step 4: Assert the work render is valid bash**

```bash
bash -n /tmp/warp-work-render.sh && echo "bash -n OK"
```

Expected: `bash -n OK` (no syntax errors, rc 0).

- [ ] **Step 5: Assert the personal render is unaffected**

```bash
cd ~/.local/share/chezmoi
(printf '{{ $_ := set . "machine_role" "personal" -}}\n'; cat .chezmoiscripts/run_onchange_before_01-install-packages.sh.tmpl) | chezmoi execute-template 2>&1 | grep -c cloudflare-warp
```

Expected: `0` (no WARP anything on personal machines).

- [ ] **Step 6: Confirm chezmoi sees only this change**

```bash
cd ~/.local/share/chezmoi
chezmoi diff
```

Expected: the only pending change is the new WARP block in the rendered `run_onchange_before_01-install-packages.sh` script (live role is `work`, so it renders). No other file appears in the diff. Do NOT run `chezmoi apply` (it needs a 1Password session and is out of scope for this plan; the actual install happens on the next normal `chezmoi apply` the user runs).

- [ ] **Step 7: Commit**

```bash
cd ~/.local/share/chezmoi
git add .chezmoiscripts/run_onchange_before_01-install-packages.sh.tmpl
git commit -m "packages: install Cloudflare WARP on work machines (isolated, warn-and-continue)"
```

Push is intentionally NOT part of this plan: the GitHub remote needs `ssh-add ~/.ssh/id_github` (passphrase, a user action). The user pushes when ready.

---

## Manual follow-up (not automated, recorded for the user)

After the next `chezmoi apply` installs the package, enroll once:

```bash
warp-cli teams-enroll <team-name>   # opens browser for Cloudflare One / IdP SSO
warp-cli connect
```

`<team-name>` is the org slug from `<team-name>.cloudflareaccess.com`. The package enables `warp-svc.service` itself. Do not run a manual WireGuard tunnel and WARP over overlapping routes at the same time (the box also provisions `wireguard-tools`).

## Self-Review

- **Spec coverage:** work-only gating (Step 2 `{{- if eq .machine_role "work" }}` + Step 5 personal-negative); isolated warn-and-continue, not in `ROLE_PACKAGES` (Step 2 note + block structure); fixed-path repo with `pubkey.gpg` + `cloudflare-warp.repo` write (Step 2 + Step 3 asserts); no secret / no enrollment / no service work (block contains none; manual follow-up section); verification renders for work + personal + `bash -n` + `chezmoi diff` (Steps 3-6). All spec sections map to a step.
- **Placeholder scan:** none. `<team-name>` / `<team>` are real user-supplied values in a manual command and a comment, explained in place, not plan placeholders.
- **Type consistency:** the repo id `cloudflare-warp-stable`, repo filename `cloudflare-warp.repo`, baseurl `https://pkg.cloudflareclient.com/rpm`, key `pubkey.gpg`, and package name `cloudflare-warp` are identical across Step 2's block and Steps 3/5's grep assertions.
