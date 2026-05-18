# Multi-account 1Password for chezmoi — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the chezmoi source apply cleanly on both a personal machine (1Password `ben-dotfiles` vault) and a work machine (1Password `Employee` vault), with no ungated `op://ben-dotfiles` reads on work.

**Architecture:** A `df_vault` chezmoi data variable derived from the existing `machine_role` prompt selects the vault. Both vaults hold an identical `dotfiles-*` item layout, so secret references differ only by vault name. Personal-only domains stay gated to `personal`; `dbc` is excluded on work.

**Tech Stack:** chezmoi v2.70 (Go text/template), 1Password CLI (`op`), bash, NetworkManager (`nmcli`).

**Spec:** `docs/superpowers/specs/2026-05-18-multi-account-1password-design.md`

**Branch:** `multi-account-1password` (already created, off `main`).

---

## Verification approach (read first)

This is a chezmoi/dotfiles repo, not a unit-tested codebase. Two hard constraints shaped the per-task checks:

- **Work role cannot be simulated on the personal dev machine.** `.chezmoi.toml.tmpl` uses `promptChoiceOnce`, which returns the already-persisted `personal` value; `chezmoi execute-template --init --promptChoice machine_role=work` is silently ignored and still renders `personal`. (Verified empirically.)
- **Rendering a whole template invokes `op`** (1Password biometric prompt), which hangs non-interactive/subagent execution.

Therefore each code task (1–9) is verified with **deterministic static assertions** (`rg`/`bash -n`/pure-template logic evals) that do **not** call `op` and do **not** depend on role. End-to-end resolution with real secrets is validated holistically by `chezmoi diff` / `chezmoi apply` on each real machine in **Tasks 10 (personal)** and **11 (work)**, which are interactive user gates where `op` prompts can be approved.

A recurring helper — a pure-template logic eval (no data, no `op`):

```bash
chezmoi execute-template '{{ printf "op://%s/dotfiles-git/config.name" "Employee" }}'   # -> op://Employee/dotfiles-git/config.name
```

This proves a `printf` reference string is well-formed independent of role.

---

## Migration safety / ordering

The spec describes renaming live personal 1Password items. A literal rename would break personal `chezmoi apply` between the rename and the template change. This plan uses an **additive** procedure reaching the same end state with zero downtime:

1. **Task 0** — *add* new `dotfiles-*` items in both vaults (copies of existing data). Old `git`/`ssh`/`vpn` items are left untouched, so personal keeps working on the old templates.
2. **Tasks 1–9** — all template edits, on the branch. Not applied to any machine yet.
3. **Task 10** — verify + apply on the personal machine (reads the new items, which now exist).
4. **Task 11** — roll out + verify on the work machine.
5. **Task 12** — only after both roles verified, delete the now-unused old items and merge.

Do the tasks strictly in order. Tasks 0, 10, 11, 12 are **manual user gates** (1Password GUI/CLI, per-machine application). Tasks 1–9 are agent-executable file edits.

---

### Task 0: 1Password — additive item creation (MANUAL — user)

Create the new items in **both** vaults. Do **not** rename or delete anything yet. Field names below must match exactly (they are the `op://` reference fields).

**Personal vault `ben-dotfiles`** — copy values from the existing items:

- `dotfiles-git`: `config.name`, `config.email` ← copied as-is from existing `op://ben-dotfiles/git/*` (keep original field names)
- `dotfiles-ssh`: `config.home`, `config.servers`, `github.privatekey`, `github.publickey`, `skund-home.privatekey`, `skund-home.publickey`, `skund-edge.privatekey`, `skund-edge.publickey` ← the same-named fields of existing `op://ben-dotfiles/ssh/*`
- `dotfiles-vpn`: `wg-home.name`, `wg-home.server-endpoint`, `wg-home.server-publickey`, `wg-home.client-dns`, `wg-home.client-privatekey`, `wg-home.client-address`, `wg-home.client-allowedips`, `wg-home.client-presharedkey` ← existing `op://ben-dotfiles/vpn/*`
- `dotfiles-wifi`: `SSID` ← `op://House/Tux/SSID`; `Passkey` ← `op://House/Tux/Passkey` (keep original field names)

**Work vault `Employee`** — create:

- `dotfiles-git`: `config.name`, `config.email` (work git identity)
- `dotfiles-ssh`: `gitlab.privatekey`, `gitlab.publickey`, `config.servers` (free-form work `Host` blocks)
- `dotfiles-wifi`: `SSID`, `Passkey` (work WPA-PSK network)

- [ ] **Step 1: Create the items above in both vaults**

- [ ] **Step 2: Verify personal items resolve**

Run on the personal machine (signed in to `op`):

```bash
for ref in \
  "op://ben-dotfiles/dotfiles-git/config.name" \
  "op://ben-dotfiles/dotfiles-git/config.email" \
  "op://ben-dotfiles/dotfiles-ssh/config.home" \
  "op://ben-dotfiles/dotfiles-ssh/config.servers" \
  "op://ben-dotfiles/dotfiles-ssh/github.privatekey" \
  "op://ben-dotfiles/dotfiles-ssh/github.publickey" \
  "op://ben-dotfiles/dotfiles-ssh/skund-home.privatekey" \
  "op://ben-dotfiles/dotfiles-ssh/skund-home.publickey" \
  "op://ben-dotfiles/dotfiles-ssh/skund-edge.privatekey" \
  "op://ben-dotfiles/dotfiles-ssh/skund-edge.publickey" \
  "op://ben-dotfiles/dotfiles-vpn/wg-home.name" \
  "op://ben-dotfiles/dotfiles-wifi/SSID" \
  "op://ben-dotfiles/dotfiles-wifi/Passkey"; do
  printf '%s -> ' "$ref"; op read "$ref" >/dev/null && echo OK || echo FAIL
done
```

Expected: every line prints `OK`. (Work `Employee` refs are verified in Task 11.)

- [ ] **Step 3: Confirm completion** before starting Task 1.

---

### Task 1: Add `df_vault` data variable

**Files:**
- Modify: `.chezmoi.toml.tmpl`

- [ ] **Step 1: Confirm `df_vault` does not exist yet**

Run:

```bash
cd ~/.local/share/chezmoi && (chezmoi data | rg -q df_vault && echo "PRESENT — unexpected") || echo "absent — OK"
```

Expected: `absent — OK`.

- [ ] **Step 2: Replace the entire `.chezmoi.toml.tmpl` with**

```
{{ $type_choices := list "desktop" "laptop" "headless" }}
{{ $machine_type := promptChoiceOnce . "machine_type" "What type of host are you on?" $type_choices }}

{{ $role_choices := list "personal" "work" }}
{{ $machine_role := promptChoiceOnce . "machine_role" "What is the user of this machine?" $role_choices }}

{{- $df_vault := "ben-dotfiles" }}
{{- if eq $machine_role "work" }}{{ $df_vault = "Employee" }}{{ end }}

[data]
machine_type = {{ $machine_type | quote }}
machine_role = {{ $machine_role | quote }}
df_vault     = {{ $df_vault | quote }}

[onepassword]
mode = "account"
```

- [ ] **Step 3: Verify the derivation logic (pure template, no data/op)**

Run:

```bash
cd ~/.local/share/chezmoi
chezmoi execute-template '{{ $v := "ben-dotfiles" }}{{ if eq "work"     "work" }}{{ $v = "Employee" }}{{ end }}{{ $v }}'
echo
chezmoi execute-template '{{ $v := "ben-dotfiles" }}{{ if eq "personal" "work" }}{{ $v = "Employee" }}{{ end }}{{ $v }}'
```

Expected: first line `Employee`, second line `ben-dotfiles`.

- [ ] **Step 4: Regenerate config and verify this machine resolves personal**

`.chezmoi.toml.tmpl` is only re-evaluated by `chezmoi init`; `promptChoiceOnce` reuses stored answers (no prompt).

Run:

```bash
cd ~/.local/share/chezmoi && chezmoi init && chezmoi data | rg df_vault
```

Expected: a line showing `df_vault` = `ben-dotfiles` (this dev machine is `personal`).

- [ ] **Step 5: Commit**

```bash
cd ~/.local/share/chezmoi
git add .chezmoi.toml.tmpl
git commit -m "feat: add df_vault data var derived from machine_role"
```

---

### Task 2: Point `dot_gitconfig.tmpl` at `dotfiles-git`

**Files:**
- Modify: `dot_gitconfig.tmpl:2-3`

- [ ] **Step 1: Replace lines 2–3**

Old:

```
    name = {{ onepasswordRead "op://ben-dotfiles/git/config.name" | quote }}
    email = {{ onepasswordRead "op://ben-dotfiles/git/config.email" | quote }}
```

New:

```
    name  = {{ onepasswordRead (printf "op://%s/dotfiles-git/config.name"  .df_vault) | quote }}
    email = {{ onepasswordRead (printf "op://%s/dotfiles-git/config.email" .df_vault) | quote }}
```

- [ ] **Step 2: Static assertions**

Run:

```bash
cd ~/.local/share/chezmoi
rg -F 'printf "op://%s/dotfiles-git/config.name"'  dot_gitconfig.tmpl
rg -F 'printf "op://%s/dotfiles-git/config.email"' dot_gitconfig.tmpl
rg -F 'op://ben-dotfiles/git/config' dot_gitconfig.tmpl && echo "OLD REF PRESENT — FAIL" || echo "old refs gone — OK"
chezmoi execute-template '{{ printf "op://%s/dotfiles-git/config.name" "Employee" }}'
```

Expected: the two `rg -F` lines match (print the line), `old refs gone — OK`, final line `op://Employee/dotfiles-git/config.name`.

- [ ] **Step 3: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_gitconfig.tmpl
git commit -m "feat: gitconfig reads dotfiles-git from role vault"
```

---

### Task 3: Role-branch `private_dot_ssh/config.tmpl`

**Files:**
- Modify: `private_dot_ssh/config.tmpl`

- [ ] **Step 1: Replace the entire file with**

```
# -- General --
# Auto-add keys to agent on first use
AddKeysToAgent yes

# -- Git --
{{- if eq .machine_role "personal" }}

Host github.com
    HostName github.com
    IdentityFile ~/.ssh/id_github
    User git
    IdentitiesOnly yes
{{- else }}

Host gitlab.com
    HostName gitlab.com
    IdentityFile ~/.ssh/id_gitlab
    User git
    IdentitiesOnly yes
{{- end }}
{{- if eq .machine_role "personal" }}

# -- Home --

{{ onepasswordRead "op://ben-dotfiles/dotfiles-ssh/config.home" }}
{{- end }}

# -- Servers --

{{ onepasswordRead (printf "op://%s/dotfiles-ssh/config.servers" .df_vault) }}
```

(`config.home` is personal-only so the literal `ben-dotfiles` is correct; `config.servers` is role-agnostic via `.df_vault`.)

- [ ] **Step 2: Static assertions**

Run:

```bash
cd ~/.local/share/chezmoi
rg -F 'Host github.com' private_dot_ssh/config.tmpl
rg -F 'Host gitlab.com' private_dot_ssh/config.tmpl
rg -F 'op://ben-dotfiles/dotfiles-ssh/config.home' private_dot_ssh/config.tmpl
rg -F 'printf "op://%s/dotfiles-ssh/config.servers" .df_vault' private_dot_ssh/config.tmpl
rg -F 'op://ben-dotfiles/ssh/config' private_dot_ssh/config.tmpl && echo "OLD REF PRESENT — FAIL" || echo "old refs gone — OK"
chezmoi execute-template '{{ if eq "work" "personal" }}github{{ else }}gitlab{{ end }}'
chezmoi execute-template '{{ if eq "personal" "personal" }}github{{ else }}gitlab{{ end }}'
```

Expected: the four `rg -F` lines match, `old refs gone — OK`, then `gitlab` then `github`.

- [ ] **Step 3: Commit**

```bash
cd ~/.local/share/chezmoi
git add private_dot_ssh/config.tmpl
git commit -m "feat: role-branch ssh config (github/personal vs gitlab/work)"
```

---

### Task 4: Split key set in `run_once_before_05-setup-ssh-keys.sh.tmpl`

**Files:**
- Modify: `.chezmoiscripts/run_once_before_05-setup-ssh-keys.sh.tmpl`

- [ ] **Step 1: Replace the entire file with**

```
#!/bin/bash
set -euo pipefail

SSH_DIR="$HOME/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

write_key() {
    local file="$1"
    local content="$2"
    local perm="$3"
    if [ ! -f "$file" ]; then
        echo "Writing $file"
        printf '%b\n' "$content" > "$file"
        chmod "$perm" "$file"
    fi
}
{{- if eq .machine_role "personal" }}

write_key "$SSH_DIR/id_github"     {{ onepasswordRead "op://ben-dotfiles/dotfiles-ssh/github.privatekey" | quote }}     600
write_key "$SSH_DIR/id_github.pub" {{ onepasswordRead "op://ben-dotfiles/dotfiles-ssh/github.publickey" | quote }}      644
write_key "$SSH_DIR/id_skund_home"     {{ onepasswordRead "op://ben-dotfiles/dotfiles-ssh/skund-home.privatekey" | quote }}     600
write_key "$SSH_DIR/id_skund_home.pub" {{ onepasswordRead "op://ben-dotfiles/dotfiles-ssh/skund-home.publickey" | quote }}      644
write_key "$SSH_DIR/id_skund_edge"     {{ onepasswordRead "op://ben-dotfiles/dotfiles-ssh/skund-edge.privatekey" | quote }}     600
write_key "$SSH_DIR/id_skund_edge.pub" {{ onepasswordRead "op://ben-dotfiles/dotfiles-ssh/skund-edge.publickey" | quote }}      644

# Add skund-home to authorized_keys
AUTH_KEYS="$SSH_DIR/authorized_keys"
SKUND_HOME_PUB={{ onepasswordRead "op://ben-dotfiles/dotfiles-ssh/skund-home.publickey" | quote }}
if [ ! -f "$AUTH_KEYS" ] || ! grep -qF "$SKUND_HOME_PUB" "$AUTH_KEYS"; then
    echo "Adding skund-home to authorized_keys"
    printf '%b\n' "$SKUND_HOME_PUB" >> "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"
fi
{{- else }}

write_key "$SSH_DIR/id_gitlab"     {{ onepasswordRead "op://Employee/dotfiles-ssh/gitlab.privatekey" | quote }}     600
write_key "$SSH_DIR/id_gitlab.pub" {{ onepasswordRead "op://Employee/dotfiles-ssh/gitlab.publickey" | quote }}      644
{{- end }}

echo "SSH keys configured"
```

(The SSH-dir setup and `write_key` helper are now shared; the key list is role-branched. Each branch names its own vault explicitly, per the spec's rule for role-branched code.)

- [ ] **Step 2: Static assertions**

Run:

```bash
cd ~/.local/share/chezmoi
f=.chezmoiscripts/run_once_before_05-setup-ssh-keys.sh.tmpl
rg -F 'op://ben-dotfiles/dotfiles-ssh/github.privatekey'  "$f"
rg -F 'op://ben-dotfiles/dotfiles-ssh/skund-edge.publickey' "$f"
rg -F 'op://Employee/dotfiles-ssh/gitlab.privatekey' "$f"
rg -F '{{- else }}' "$f"
rg -cF 'write_key()' "$f"
rg -F 'op://ben-dotfiles/ssh/' "$f" && echo "OLD REF PRESENT — FAIL" || echo "old refs gone — OK"
```

Expected: the first three `rg -F` lines match; `{{- else }}` matches; `rg -cF 'write_key()'` prints `1` (helper defined exactly once, shared); `old refs gone — OK`.

- [ ] **Step 3: Commit**

```bash
cd ~/.local/share/chezmoi
git add .chezmoiscripts/run_once_before_05-setup-ssh-keys.sh.tmpl
git commit -m "feat: split ssh key provisioning by role (skund/github vs gitlab)"
```

---

### Task 5: Make WiFi setup role-agnostic

**Files:**
- Modify: `.chezmoiscripts/run_once_before_06-setup-wifi.sh.tmpl`

- [ ] **Step 1: Replace the entire file with**

```
#!/bin/bash
set -euo pipefail

# Skip if no wireless interface is available
if ! nmcli device status | grep -q wifi; then
    echo "No wifi interface found, skipping"
    exit 0
fi

WIFI_SSID={{ onepasswordRead (printf "op://%s/dotfiles-wifi/SSID" .df_vault) | quote }}
WIFI_PASSWORD={{ onepasswordRead (printf "op://%s/dotfiles-wifi/Passkey" .df_vault) | quote }}

# Check if connection already exists
if nmcli connection show "$WIFI_SSID" &>/dev/null; then
    echo "WiFi connection '$WIFI_SSID' already configured"
    exit 0
fi

echo "Creating WiFi connection: $WIFI_SSID"
nmcli connection add \
    type wifi \
    con-name "$WIFI_SSID" \
    ssid "$WIFI_SSID" \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk "$WIFI_PASSWORD" \
    wifi.cloned-mac-address permanent \
    connection.autoconnect yes

echo "WiFi connection '$WIFI_SSID' created"
```

(The `{{- if eq .machine_role "personal" }}` / `{{- end }}` gate is removed; vault comes from `.df_vault`. WPA-PSK is correct for both roles.)

- [ ] **Step 2: Static assertions**

Run:

```bash
cd ~/.local/share/chezmoi
f=.chezmoiscripts/run_once_before_06-setup-wifi.sh.tmpl
rg -F 'printf "op://%s/dotfiles-wifi/SSID" .df_vault' "$f"
rg -F 'printf "op://%s/dotfiles-wifi/Passkey" .df_vault' "$f"
rg -F 'wifi-sec.key-mgmt wpa-psk' "$f"
rg -F 'eq .machine_role "personal"' "$f" && echo "ROLE GATE STILL PRESENT — FAIL" || echo "gate removed — OK"
rg -F 'op://House/Tux' "$f" && echo "OLD REF PRESENT — FAIL" || echo "old refs gone — OK"
```

Expected: first three `rg -F` lines match; `gate removed — OK`; `old refs gone — OK`.

- [ ] **Step 3: Commit**

```bash
cd ~/.local/share/chezmoi
git add .chezmoiscripts/run_once_before_06-setup-wifi.sh.tmpl
git commit -m "feat: wifi setup role-agnostic via df_vault"
```

---

### Task 6: Repoint WireGuard refs to `dotfiles-vpn`

**Files:**
- Modify: `.chezmoiscripts/run_once_before_07-setup-wireguard.sh.tmpl:17,19-25`

The script stays gated `{{- if and (eq .machine_role "personal") (eq .machine_type "laptop") }}`. Only the eight `onepasswordRead` references change.

- [ ] **Step 1: Replace line 17**

Old:

```
BASE_NAME="wg-{{ onepasswordRead "op://ben-dotfiles/vpn/wg-home.name" }}"
```

New:

```
BASE_NAME="wg-{{ onepasswordRead (printf "op://%s/dotfiles-vpn/wg-home.name" .df_vault) }}"
```

- [ ] **Step 2: Replace lines 19–25**

Old:

```
WG_SERVER_ENDPOINT={{ onepasswordRead "op://ben-dotfiles/vpn/wg-home.server-endpoint" | quote }}
WG_SERVER_PUBLICKEY={{ onepasswordRead "op://ben-dotfiles/vpn/wg-home.server-publickey" | quote }}
WG_CLIENT_DNS={{ onepasswordRead "op://ben-dotfiles/vpn/wg-home.client-dns" | quote }}
WG_CLIENT_PRIVATEKEY={{ onepasswordRead "op://ben-dotfiles/vpn/wg-home.client-privatekey" | quote }}
WG_CLIENT_ADDRESS={{ onepasswordRead "op://ben-dotfiles/vpn/wg-home.client-address" | quote }}
WG_CLIENT_ALLOWED_IPS={{ onepasswordRead "op://ben-dotfiles/vpn/wg-home.client-allowedips" | quote }}
WG_CLIENT_PRESHAREDKEY={{ onepasswordRead "op://ben-dotfiles/vpn/wg-home.client-presharedkey" | quote }}
```

New:

```
WG_SERVER_ENDPOINT={{ onepasswordRead (printf "op://%s/dotfiles-vpn/wg-home.server-endpoint" .df_vault) | quote }}
WG_SERVER_PUBLICKEY={{ onepasswordRead (printf "op://%s/dotfiles-vpn/wg-home.server-publickey" .df_vault) | quote }}
WG_CLIENT_DNS={{ onepasswordRead (printf "op://%s/dotfiles-vpn/wg-home.client-dns" .df_vault) | quote }}
WG_CLIENT_PRIVATEKEY={{ onepasswordRead (printf "op://%s/dotfiles-vpn/wg-home.client-privatekey" .df_vault) | quote }}
WG_CLIENT_ADDRESS={{ onepasswordRead (printf "op://%s/dotfiles-vpn/wg-home.client-address" .df_vault) | quote }}
WG_CLIENT_ALLOWED_IPS={{ onepasswordRead (printf "op://%s/dotfiles-vpn/wg-home.client-allowedips" .df_vault) | quote }}
WG_CLIENT_PRESHAREDKEY={{ onepasswordRead (printf "op://%s/dotfiles-vpn/wg-home.client-presharedkey" .df_vault) | quote }}
```

- [ ] **Step 3: Static assertions**

Run:

```bash
cd ~/.local/share/chezmoi
f=.chezmoiscripts/run_once_before_07-setup-wireguard.sh.tmpl
rg -F 'op://ben-dotfiles/vpn/' "$f" && echo "OLD REF PRESENT — FAIL" || echo "old refs gone — OK"
echo "dotfiles-vpn refs: $(rg -cF 'op://%s/dotfiles-vpn/wg-home.' "$f")"
rg -F 'and (eq .machine_role "personal") (eq .machine_type "laptop")' "$f"
```

Expected: `old refs gone — OK`; `dotfiles-vpn refs: 8`; the gate line matches (unchanged).

- [ ] **Step 4: Commit**

```bash
cd ~/.local/share/chezmoi
git add .chezmoiscripts/run_once_before_07-setup-wireguard.sh.tmpl
git commit -m "refactor: wireguard refs use dotfiles-vpn via df_vault"
```

---

### Task 7: Repoint `dbc` WireGuard ref

**Files:**
- Modify: `private_dot_local/private_bin/executable_dbc.tmpl:5`

- [ ] **Step 1: Replace line 5**

Old:

```
WG_IFACE="${WG_IFACE:-wg-{{ onepasswordRead "op://ben-dotfiles/vpn/wg-home.name" }}}"
```

New:

```
WG_IFACE="${WG_IFACE:-wg-{{ onepasswordRead (printf "op://%s/dotfiles-vpn/wg-home.name" .df_vault) }}}"
```

- [ ] **Step 2: Static assertions**

Run:

```bash
cd ~/.local/share/chezmoi
f=private_dot_local/private_bin/executable_dbc.tmpl
rg -F 'printf "op://%s/dotfiles-vpn/wg-home.name" .df_vault' "$f"
rg -F 'op://ben-dotfiles/vpn/' "$f" && echo "OLD REF PRESENT — FAIL" || echo "old refs gone — OK"
```

Expected: the `rg -F` line matches; `old refs gone — OK`.

- [ ] **Step 3: Commit**

```bash
cd ~/.local/share/chezmoi
git add private_dot_local/private_bin/executable_dbc.tmpl
git commit -m "refactor: dbc wireguard ref uses dotfiles-vpn via df_vault"
```

---

### Task 8: Exclude `dbc` on work via `.chezmoiignore`

**Files:**
- Modify: `.chezmoiignore`

- [ ] **Step 1: Replace the entire file with**

```
{{- if eq .machine_type "headless" }}
.config/sway
.config/waybar
.config/gammastep
.local/bin/sway-cheatsheet
{{- end }}
{{- if eq .machine_role "work" }}
.local/bin/dbc
{{- end }}
```

- [ ] **Step 2: Static assertions + real personal check**

Run:

```bash
cd ~/.local/share/chezmoi
rg -F '{{- if eq .machine_role "work" }}' .chezmoiignore
rg -F '.local/bin/dbc' .chezmoiignore
rg -F '.local/bin/sway-cheatsheet' .chezmoiignore
(chezmoi ignored | rg -q 'bin/dbc' && echo "dbc IGNORED ON PERSONAL — FAIL") || echo "dbc not ignored on personal — OK"
```

Expected: the three `rg -F` lines match (headless block intact, work block added); `dbc not ignored on personal — OK`. (That `dbc` *is* ignored on work is verified on the work machine in Task 11.)

- [ ] **Step 3: Commit**

```bash
cd ~/.local/share/chezmoi
git add .chezmoiignore
git commit -m "feat: exclude .local/bin/dbc on work machines"
```

---

### Task 9: Make `bootstrap.sh` account-agnostic

**Files:**
- Modify: `bootstrap.sh:35-39`

`bootstrap.sh` is plain bash (not a chezmoi template), so `bash -n` is a valid syntax check.

- [ ] **Step 1: Replace lines 35–39**

Old:

```
# Verify we can access the vault
if ! op vault get ben-dotfiles &>/dev/null; then
    echo "ERROR: Cannot access ben-dotfiles vault. Check your 1Password account."
    exit 1
fi
```

New:

```
# Verify we're signed in to 1Password (chezmoi pulls from the
# role-appropriate vault during init)
if ! op whoami &>/dev/null; then
    echo "ERROR: Not signed in to 1Password. Run 'op signin' and retry."
    exit 1
fi
```

- [ ] **Step 2: Static assertions**

Run:

```bash
cd ~/.local/share/chezmoi
bash -n bootstrap.sh && echo "syntax OK"
rg -F 'op whoami' bootstrap.sh
rg -F 'ben-dotfiles' bootstrap.sh && echo "ben-dotfiles STILL PRESENT — FAIL" || echo "no ben-dotfiles refs — OK"
```

Expected: `syntax OK`; the `op whoami` line matches; `no ben-dotfiles refs — OK`.

- [ ] **Step 3: Commit**

```bash
cd ~/.local/share/chezmoi
git add bootstrap.sh
git commit -m "fix: bootstrap checks op sign-in, not a specific vault"
```

---

### Task 10: Verify + apply on the personal machine (MANUAL — user, interactive)

- [ ] **Step 1: Confirm no stale references remain in tracked templates**

Run:

```bash
cd ~/.local/share/chezmoi
git ls-files | rg -v '^docs/' \
  | xargs rg -nF -e 'op://ben-dotfiles/git/' -e 'op://ben-dotfiles/ssh/' \
                 -e 'op://ben-dotfiles/vpn/' -e 'op://House/Tux' \
  && echo "STALE REFS FOUND — investigate" || echo "no stale refs — OK"
```

Expected: `no stale refs — OK`. (Old paths must exist only in 1Password until Task 12, never in templates.)

- [ ] **Step 2: Dry-run the full apply**

Run:

```bash
cd ~/.local/share/chezmoi && chezmoi init && chezmoi diff
```

Expected: an empty (or whitespace-only) diff — the regenerated `~/.gitconfig`, `~/.ssh/config`, scripts, etc. are byte-identical to current, because the new `dotfiles-*` items hold the same values as the old items. Approve any `op` prompt.

- [ ] **Step 3: Apply**

Run:

```bash
cd ~/.local/share/chezmoi && chezmoi apply --verbose
```

Expected: completes with no `op://` errors. Spot-check `~/.gitconfig`, `~/.ssh/config`, and (laptop only) `nmcli connection show` lists the `wg-*` profiles.

- [ ] **Step 4: Confirm personal is healthy** before proceeding.

---

### Task 11: Roll out + verify on the work machine (MANUAL — user, interactive)

On the work machine `.machine_role` is genuinely `work`, so rendering exercises the work branches for real.

- [ ] **Step 1: Get the branch onto the machine**

Fresh machine: run `bootstrap.sh` from the branch; during `chezmoi init` answer `machine_role` = `work`, `machine_type` accordingly. Existing machine: pull the `multi-account-1password` branch in `~/.local/share/chezmoi`, then `chezmoi init`.

- [ ] **Step 2: Confirm sign-in and work items resolve**

Run on the work machine:

```bash
op whoami && for ref in \
  "op://Employee/dotfiles-git/config.name" \
  "op://Employee/dotfiles-git/config.email" \
  "op://Employee/dotfiles-ssh/gitlab.privatekey" \
  "op://Employee/dotfiles-ssh/gitlab.publickey" \
  "op://Employee/dotfiles-ssh/config.servers" \
  "op://Employee/dotfiles-wifi/SSID" \
  "op://Employee/dotfiles-wifi/Passkey"; do
  printf '%s -> ' "$ref"; op read "$ref" >/dev/null && echo OK || echo FAIL
done
```

Expected: `op whoami` succeeds; every ref prints `OK`.

- [ ] **Step 3: Dry-run, apply, and verify outcomes**

Run:

```bash
cd ~/.local/share/chezmoi && chezmoi diff && chezmoi apply --verbose
chezmoi ignored | rg 'bin/dbc' && echo "dbc correctly ignored on work" || echo "dbc NOT ignored — FAIL"
test -f ~/.local/bin/dbc && echo "dbc PRESENT — FAIL" || echo "dbc absent — OK"
```

Expected: no `op://ben-dotfiles` reference errors. `~/.gitconfig` has the work identity; `~/.ssh/config` contains `Host gitlab.com` + the work server blocks; `~/.ssh/id_gitlab` exists (mode 600); WiFi connection created; `dbc correctly ignored on work`; `dbc absent — OK`.

- [ ] **Step 4: Confirm work is healthy** before proceeding.

---

### Task 12: 1Password cleanup + merge (MANUAL — user)

Only after Tasks 10 and 11 both pass.

- [ ] **Step 1: Delete the now-unused old personal items**

In `ben-dotfiles`, delete items `git`, `ssh`, `vpn`. Leave the `House` vault and its `Tux` item in place (no longer referenced by dotfiles, but kept for other uses).

- [ ] **Step 2: Final regression check on personal**

Run:

```bash
cd ~/.local/share/chezmoi && chezmoi init && chezmoi diff
```

Expected: still an empty diff (templates reference only `dotfiles-*` items, which remain).

- [ ] **Step 3: Merge the branch**

```bash
cd ~/.local/share/chezmoi
git switch main
git merge --no-ff multi-account-1password -m "feat: multi-account 1Password (personal/work vaults)"
git push
```

---

## Notes for the executor

- `chezmoi execute-template` is used in this plan only for **pure-template logic evals** (literal args, no data, no `op`) — safe and deterministic in automated/non-TTY execution.
- Never add `chezmoi execute-template < <file>` of a real template to a code task: it invokes `op` (biometric) and depends on role. Whole-template, secret-resolving validation is intentionally concentrated in the interactive user gates (Tasks 10, 11).
- `--promptChoice machine_role=work` does **not** override `promptChoiceOnce`'s persisted value; do not rely on it to simulate the work role on the personal machine.
- Tasks 0, 10, 11, 12 require human action and are gates — do not automate or reorder them.
- Each code task (1–9) is independently committable and leaves the branch consistent; nothing is applied to a live machine until Task 10.
