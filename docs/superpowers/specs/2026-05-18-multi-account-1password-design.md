# Multi-account 1Password for chezmoi — design

**Date:** 2026-05-18
**Status:** Approved

## Problem

The chezmoi source is shared across a personal machine and a work machine. The
personal 1Password account has a `ben-dotfiles` vault; the work account does
**not** — its only usable vault is the per-employee `Employee` vault, and a new
vault cannot be created there.

Today several templates read `op://ben-dotfiles/...` unconditionally, so a work
`chezmoi apply` breaks:

- `dot_gitconfig.tmpl` — reads `op://ben-dotfiles/git/config.{name,email}` ungated.
- `executable_dbc.tmpl` — reads `op://ben-dotfiles/vpn/wg-home.name` ungated.
- `bootstrap.sh` — hard-exits if the `ben-dotfiles` vault is not accessible.

1Password has **no folders**: a secret reference is
`op://<vault>/<item>/[<section>/]<field>` and that is the only nesting. So
organisation within the shared `Employee` vault is done with an item-name
prefix.

## Model

A new chezmoi data variable `df_vault` is derived from the existing
`machine_role` prompt:

| `machine_role` | `df_vault`     |
| -------------- | -------------- |
| `personal`     | `ben-dotfiles` |
| `work`         | `Employee`     |

Every dotfiles secret reference becomes
`op://{{ .df_vault }}/dotfiles-<domain>/<field>`. Both vaults hold an
**identical `dotfiles-*` item layout**; only the vault name differs. The
`dotfiles-` prefix groups the items together alphabetically in the shared
`Employee` vault (it acts as the "folder" 1Password does not provide).

Personal-only domains (home SSH, WireGuard, devbox) have no work counterpart
and stay gated to `personal`.

## 1Password layout (manual migration, done in the 1Password apps)

Identical item names in both vaults; only contents differ.

| item            | personal `ben-dotfiles`                                                                                              | work `Employee`                                  |
| --------------- | ------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| `dotfiles-git`  | `name`, `email`                                                                                                     | `name`, `email` (work values)                    |
| `dotfiles-ssh`  | `config.home`, `config.servers`, `github.privatekey`, `github.publickey`, `skund-home.privatekey`, `skund-home.publickey`, `skund-edge.privatekey`, `skund-edge.publickey` | `config.servers`, `gitlab.privatekey`, `gitlab.publickey` |
| `dotfiles-vpn`  | `wg-home.*` (all current `vpn` fields)                                                                               | — (work VPN added later, out of scope)           |
| `dotfiles-wifi` | `ssid`, `password` (migrated from `op://House/Tux/SSID` + `Passkey`)                                                 | `ssid`, `password` (work network, WPA-PSK)       |

Migration steps:

1. Personal: rename item `git` → `dotfiles-git`, fields → `name`, `email`.
2. Personal: rename item `ssh` → `dotfiles-ssh`, keep existing field names
   (`config.home`, `config.servers`, `github.*`, `skund-home.*`,
   `skund-edge.*`).
3. Personal: rename item `vpn` → `dotfiles-vpn`, keep `wg-home.*` fields.
4. Personal: create item `dotfiles-wifi` with `ssid`, `password` copied from
   `op://House/Tux/SSID` and `op://House/Tux/Passkey`.
5. Work: create `dotfiles-git` (`name`, `email`), `dotfiles-ssh`
   (`gitlab.privatekey`, `gitlab.publickey`, `config.servers`), `dotfiles-wifi`
   (`ssid`, `password`).

The `House` vault is no longer referenced by dotfiles after step 4; it is left
in place for other uses.

## Code-path classification by role

**Role-agnostic, ungated** (resolve via `{{ .df_vault }}`, run on both):

- `dot_gitconfig.tmpl`
- `.chezmoiscripts/run_once_before_06-setup-wifi.sh.tmpl`
- the `config.servers` block of `private_dot_ssh/config.tmpl`

**Role-branched** (different content per role):

- `private_dot_ssh/config.tmpl` — git host block and `config.home`
- `.chezmoiscripts/run_once_before_05-setup-ssh-keys.sh.tmpl` — key set

**Personal-only, gated `personal` as today** (only the `vpn` → `dotfiles-vpn`
rename):

- `.chezmoiscripts/run_once_before_07-setup-wireguard.sh.tmpl`

**Excluded on work** via `.chezmoiignore`:

- `.local/bin/dbc` (source `private_dot_local/private_bin/executable_dbc.tmpl`)

## File changes

### `.chezmoi.toml.tmpl`

After the existing `machine_role` prompt, derive `df_vault` and add it to
`[data]`:

```
{{- $df_vault := "ben-dotfiles" }}
{{- if eq $machine_role "work" }}{{ $df_vault = "Employee" }}{{ end }}

[data]
machine_type = {{ $machine_type | quote }}
machine_role = {{ $machine_role | quote }}
df_vault     = {{ $df_vault | quote }}
```

### `dot_gitconfig.tmpl`

```
[user]
    name  = {{ onepasswordRead (printf "op://%s/dotfiles-git/name"  .df_vault) | quote }}
    email = {{ onepasswordRead (printf "op://%s/dotfiles-git/email" .df_vault) | quote }}
```

No gating — both vaults have `dotfiles-git`. Fixes a current work breakage.

### `private_dot_ssh/config.tmpl`

- Git host block becomes role-branched:
  - personal → `Host github.com`, `IdentityFile ~/.ssh/id_github`
  - work → `Host gitlab.com`, `IdentityFile ~/.ssh/id_gitlab`
- `# -- Home --` block (`config.home`) stays personal-only.
- `# -- Servers --` block (`config.servers`) becomes role-agnostic and ungated,
  using `printf "op://%s/dotfiles-ssh/config.servers" .df_vault`.

Resulting shape:

```
# -- General --
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

### `.chezmoiscripts/run_once_before_05-setup-ssh-keys.sh.tmpl`

Split the existing personal-gated body into two role branches:

- personal: write `id_github`(+`.pub`), `id_skund_home`(+`.pub`),
  `id_skund_edge`(+`.pub`) from `op://ben-dotfiles/dotfiles-ssh/*`; keep the
  existing `skund-home.publickey` → `authorized_keys` step (personal-only).
- work: write `id_gitlab`(+`.pub`) from
  `op://Employee/dotfiles-ssh/gitlab.{privatekey,publickey}`.

References use the renamed `dotfiles-ssh` item.

### `.chezmoiscripts/run_once_before_06-setup-wifi.sh.tmpl`

Remove the `{{- if eq .machine_role "personal" }}` gate. Read from the
role-resolved vault:

```
WIFI_SSID={{ onepasswordRead (printf "op://%s/dotfiles-wifi/ssid"     .df_vault) | quote }}
WIFI_PASSWORD={{ onepasswordRead (printf "op://%s/dotfiles-wifi/password" .df_vault) | quote }}
```

The existing "no wifi interface, skip" guard still covers wired desktops.
Auth stays WPA-PSK for both roles.

### `.chezmoiscripts/run_once_before_07-setup-wireguard.sh.tmpl`

Stays gated `{{- if and (eq .machine_role "personal") (eq .machine_type
"laptop") }}`. Only change: `op://ben-dotfiles/vpn/wg-home.*` →
`op://ben-dotfiles/dotfiles-vpn/wg-home.*` (literal `ben-dotfiles` is fine here
since the branch is personal-only; `printf` with `.df_vault` is acceptable too
for uniformity).

### `private_dot_local/private_bin/executable_dbc.tmpl`

- Rename its op ref `op://ben-dotfiles/vpn/wg-home.name` →
  `op://ben-dotfiles/dotfiles-vpn/wg-home.name`.
- Exclude on work by adding to `.chezmoiignore`:

```
{{- if eq .machine_role "work" }}
.local/bin/dbc
{{- end }}
```

This removes the only remaining ungated `op://ben-dotfiles` read on work.

### `bootstrap.sh`

Replace the brittle vault-specific check (currently lines 36–39):

```
if ! op vault get ben-dotfiles &>/dev/null; then
    echo "ERROR: Cannot access ben-dotfiles vault. Check your 1Password account."
    exit 1
fi
```

with a generic signed-in check, e.g.:

```
if ! op whoami &>/dev/null; then
    echo "ERROR: Not signed in to 1Password. Run 'op signin' and retry."
    exit 1
fi
```

`chezmoi init` then prompts for `machine_role` and pulls from the correct
vault; a missing `dotfiles-*` item surfaces as a clear chezmoi error rather
than a pre-flight failure that is wrong for the work account.

## Out of scope (deliberate)

- Work WireGuard/VPN — added later by the user; WireGuard stays personal-gated.
- Converting SSH items to native 1Password "SSH Key" type / SSH agent — the
  current file-writing approach via `onepasswordRead` is kept.
- The `House` WiFi vault — left in place, simply no longer referenced.
- Bootstrap remains Fedora/`dnf`-based; the work machine is assumed to be the
  same family (the `install-packages` script already branches `personal`/`work`).
- Multi-account `op signin --account ...` selection — assumes each machine has
  its single relevant 1Password account configured.

## Verification

For each role, before applying:

- `chezmoi execute-template < dot_gitconfig.tmpl` (and the SSH config / script
  templates) with `machine_role` set, confirming the correct `op://` paths
  resolve.
- `chezmoi apply --dry-run --verbose` on each machine.

Success criteria:

- Personal machine: behaviour unchanged after the vault-item renames.
- Work machine: `chezmoi init --apply` completes with no `op://ben-dotfiles`
  reference errors; git identity, GitLab SSH key, WiFi, and work server SSH
  config are all provisioned from `Employee`.
