# Enable warp-taskbar user service on work machines Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Revision (2026-05-19):** approach changed from `systemctl --user enable` (guarded by `! is-enabled`) to `systemctl --user add-wants graphical-session.target` (guarded by `! is-active`) after code-quality review showed the `enable` form silently no-ops if `warp-taskbar.service` ships `static`. See the spec's Revision note. This plan reflects the revised approach.

**Goal:** On work machines only, have chezmoi wire the `warp-taskbar.service` user unit (the Cloudflare WARP tray, shipped by `cloudflare-warp`) into `graphical-session.target` so it autostarts.

**Architecture:** `git mv` the existing user-services script to a `.tmpl`, then append one `{{- if eq .machine_role "work" }}` block after the existing `ssh-agent`/`tmux` loop. The block is guarded by `rpm -q cloudflare-warp` (the WARP install is warn-and-continue, so the package may be absent) and `! systemctl --user is-active warp-taskbar.service` (idempotent); it runs `systemctl --user add-wants graphical-session.target warp-taskbar.service` then a tolerated `start`. `add-wants` is used instead of `enable` because it is correct whether the unit ships with an `[Install]` section or as `static`. Script `01` (the WARP install) and the waybar config are untouched.

**Tech Stack:** chezmoi (Go text/template over bash), systemd `--user` units, Fedora `rpm`. Validation is `chezmoi execute-template` renders + `bash -n` + `chezmoi diff` (this repo has no build/test framework; chezmoi itself is the test, per its CLAUDE.md). `chezmoi apply` is NOT run (needs a 1Password session; out of scope).

Spec: `docs/superpowers/specs/2026-05-19-warp-taskbar-user-service-design.md`.
Depends on: `docs/superpowers/specs/2026-05-19-cloudflare-warp-chezmoi-design.md` (already implemented, commit `9c06dec`).

---

### Task 1: Work-only warp-taskbar enablement in script 09

**Files:**
- Rename + modify: `.chezmoiscripts/run_once_after_09-setup-user-services.sh` -> `.chezmoiscripts/run_once_after_09-setup-user-services.sh.tmpl`

All commands run from the chezmoi source dir: `cd ~/.local/share/chezmoi`.

- [ ] **Step 1: Confirm the RED baseline**

```bash
cd ~/.local/share/chezmoi
ls .chezmoiscripts/run_once_after_09-setup-user-services.sh
(printf '{{ $_ := set . "machine_role" "work" -}}\n'; cat .chezmoiscripts/run_once_after_09-setup-user-services.sh) | chezmoi execute-template 2>/dev/null | grep -c warp-taskbar
```

Expected: the `.sh` file exists; `grep -c warp-taskbar` prints `0` (and exits 1 because 0 matches, which is expected). This is the failing-test state: the work render SHOULD contain `warp-taskbar` after the change but does not yet.

- [ ] **Step 2: Rename the script to a template (preserve history)**

```bash
cd ~/.local/share/chezmoi
git mv .chezmoiscripts/run_once_after_09-setup-user-services.sh .chezmoiscripts/run_once_after_09-setup-user-services.sh.tmpl
```

The body has no `{{ }}`, so this is identity-safe (already verified: rendering the current body is byte-identical to it). Do not modify the body in this step.

- [ ] **Step 3: Append the work-gated block**

Edit `.chezmoiscripts/run_once_after_09-setup-user-services.sh.tmpl`. Find this exact unique 3-line tail:

```
done

echo "User services configured"
```

Replace it with EXACTLY (preserving the existing `done` and final `echo`, inserting the templated block between them; reproduce the `{{- ... }}` delimiters and indentation verbatim):

```
done
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

echo "User services configured"
```

Notes for the implementer:
- The existing `ssh-agent`/`tmux` loop and the `systemctl --user daemon-reload` line stay exactly as-is. Only the tail above changes.
- Use `add-wants graphical-session.target`, NOT `enable` and NOT `enable --now`. Rationale (do not "simplify" to `enable`): `enable` silently no-ops on a `static` unit (and `is-enabled` returns 0 for `static`, so an `is-enabled` guard would skip the block); `add-wants` is correct for both `[Install]` and `static` units. `--now` would start a tray in a possibly non-graphical apply context and fail under `set -euo pipefail`; the separate tolerated `start ... ||` handles start-now safely.
- The idempotency guard is `! systemctl --user is-active warp-taskbar.service` (NOT `is-enabled`). Re-running `add-wants` on an existing symlink is itself a harmless no-op.
- No em-dash or en-dash anywhere (user global rule). The block above is dash-free; keep it so. Leave any pre-existing dashes in other files untouched.
- Template trimming check: `done\n{{- if ... }}` renders (work) as `done`, blank line, then the comment; (personal) the whole block is omitted and it renders as `done`, blank line, `echo "User services configured"` (identical to today).
- File ends with a single trailing newline after the final `echo` line (it already does; preserve it).

- [ ] **Step 4: Assert GREEN for the work render**

```bash
cd ~/.local/share/chezmoi
(printf '{{ $_ := set . "machine_role" "work" -}}\n'; cat .chezmoiscripts/run_once_after_09-setup-user-services.sh.tmpl) | chezmoi execute-template 2>/dev/null > /tmp/svc-work-render.sh
grep -q 'rpm -q cloudflare-warp &>/dev/null' /tmp/svc-work-render.sh && echo "rpm guard OK"
grep -q '! systemctl --user is-active warp-taskbar.service' /tmp/svc-work-render.sh && echo "is-active guard OK"
grep -q 'systemctl --user add-wants graphical-session.target warp-taskbar.service' /tmp/svc-work-render.sh && echo "add-wants OK"
grep -q 'systemctl --user start warp-taskbar.service' /tmp/svc-work-render.sh && echo "tolerated start OK"
grep -q 'for svc in ssh-agent.service tmux.service; do' /tmp/svc-work-render.sh && echo "existing loop intact OK"
grep -q 'systemctl --user daemon-reload' /tmp/svc-work-render.sh && echo "daemon-reload intact OK"
! grep -q 'is-enabled warp-taskbar' /tmp/svc-work-render.sh && ! grep -q 'enable warp-taskbar' /tmp/svc-work-render.sh && echo "no enable/is-enabled on warp-taskbar OK"
```

Expected: all seven lines print (`rpm guard OK`, `is-active guard OK`, `add-wants OK`, `tolerated start OK`, `existing loop intact OK`, `daemon-reload intact OK`, `no enable/is-enabled on warp-taskbar OK`).

- [ ] **Step 5: Assert the work render is valid bash**

```bash
bash -n /tmp/svc-work-render.sh && echo "bash -n OK"
```

Expected: `bash -n OK` (rc 0).

- [ ] **Step 6: Assert the personal render is unaffected**

```bash
cd ~/.local/share/chezmoi
(printf '{{ $_ := set . "machine_role" "personal" -}}\n'; cat .chezmoiscripts/run_once_after_09-setup-user-services.sh.tmpl) | chezmoi execute-template 2>/dev/null > /tmp/svc-personal-render.sh
grep -c warp-taskbar /tmp/svc-personal-render.sh
grep -q 'for svc in ssh-agent.service tmux.service; do' /tmp/svc-personal-render.sh && echo "loop still present OK"
diff <(printf '#!/bin/bash\nset -euo pipefail\n\necho "Enabling user services..."\n\nsystemctl --user daemon-reload\n\nfor svc in ssh-agent.service tmux.service; do\n    if ! systemctl --user is-enabled "$svc" &>/dev/null; then\n        echo "Enabling $svc"\n        systemctl --user enable --now "$svc"\n    fi\ndone\n\necho "User services configured"\n') /tmp/svc-personal-render.sh && echo "personal render identical to original .sh OK"
```

Expected: `grep -c warp-taskbar` prints `0` (exit 1, expected); `loop still present OK`; `personal render identical to original .sh OK` (the personal render is byte-identical to the pre-change script body).

- [ ] **Step 7: Confirm chezmoi sees only this change**

```bash
cd ~/.local/share/chezmoi
git status --porcelain
chezmoi diff
```

Expected: `git status` shows the rename (`R  .chezmoiscripts/...sh -> ...sh.tmpl`) plus the content modification, and nothing else. `chezmoi diff` shows only the pending `run_once_after_09-setup-user-services.sh` script (live role is `work`, so the warp-taskbar block is present); no other file changes. `chezmoi diff` may exit non-zero due to the pre-existing 1Password-gated SSH-key script (documented, unrelated); that is expected. Do NOT run `chezmoi apply`.

- [ ] **Step 8: Commit**

```bash
cd ~/.local/share/chezmoi
git add .chezmoiscripts/run_once_after_09-setup-user-services.sh.tmpl
git commit -m "user-services: autostart warp-taskbar tray on work machines via add-wants"
git rev-parse HEAD
git rev-parse HEAD~1
```

`git mv` already staged the rename; `git add` on the new path stages the body change. Report both SHAs (HEAD and HEAD~1) so the controller can scope code review. Push is NOT part of this plan (the user pushes when ready).

---

## Manual follow-up (recorded for the user)

After the next `chezmoi apply` on the work box (which runs script 01 then script 09): if that apply ran inside the graphical session the tray starts immediately; otherwise it autostarts at the next graphical login via the `graphical-session.target` wants symlink. The waybar `tray` module already renders it. `warp-cli connect|disconnect|status` remains the reliable control path; the tray is a convenience. On that first apply, confirm the WARP tray icon actually appears in waybar and `systemctl --user is-active warp-taskbar.service` reports active inside the Sway graphical session (the only thing not verifiable in the dev environment, since the package is work-only). The `add-wants` approach is install-type-independent, so there is no longer a `static`-vs-`[Install]` assumption to verify.

## Self-Review

- **Spec coverage:** rename to `.tmpl` (Step 2); work-gated block appended after the loop with `rpm -q` + `is-active` guards, `add-wants graphical-session.target` + tolerated `start` (Step 3); script 01 / waybar untouched (only file 09 in Steps 7-8); personal renders nothing and the existing loop is preserved (Step 6, including byte-identical assertion); verification via work render asserts (including the negative assertion that `enable`/`is-enabled` are NOT used on warp-taskbar) + `bash -n` + personal render + `chezmoi diff` + no dashes (Steps 4-7 and the Step 3 no-dash note). Every spec section, including the Revision note's `add-wants`/`is-active` requirement, maps to a step.
- **Placeholder scan:** none. No TBD/TODO; all code shown in full; commands have expected output.
- **Type/name consistency:** `warp-taskbar.service`, `cloudflare-warp`, `graphical-session.target`, `is-active`, `add-wants`, `run_once_after_09-setup-user-services.sh.tmpl` are spelled identically across Step 3's block and Steps 4/6/7/8 assertions and commands. The Step 6 `diff` heredoc exactly reproduces the current script body verified in this session (identity-render confirmed).
