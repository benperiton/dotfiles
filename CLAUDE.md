# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

This is the **chezmoi source directory** (`chezmoi source-path` → `~/.local/share/chezmoi`),
not a normal project. Files here are *source state* that chezmoi renders and deploys into
`$HOME`. The deployed copies in `$HOME` are generated artifacts.

**Editing workflow:** edit the source file *here*, preview with `chezmoi diff`, then
`chezmoi apply`. Never edit the deployed file in `$HOME` — it will be overwritten and the
change won't be tracked. `git` operations happen directly in this directory.

Target: a fresh Fedora install (`dnf`), Sway/Wayland desktop. Upstream is
`github.com:benperiton/dotfiles`; bootstrap pulls with `chezmoi init --apply benperiton`.

## Naming conventions (source → target)

chezmoi derives the target path/attributes from the source filename:

- `dot_foo` → `~/.foo`; `private_` → mode 0600 / no group+other; `executable_` → +x
- `*.tmpl` → rendered as a Go text/template before deploy
- `.chezmoiscripts/run_<before|after>_NN-name.sh` → hook scripts (see below)
- `.chezmoi*.toml(.tmpl)` → chezmoi's own config, not deployed

`.chezmoiignore` patterns match **target** paths (relative to `$HOME`), not source filenames.

## The central concept: two-axis machine model

Everything branches on two variables, prompted **once** at `chezmoi init` via
`promptChoiceOnce` in `.chezmoi.toml.tmpl` and stored in `[data]`:

- `machine_type`: `desktop` | `laptop` | `headless`
- `machine_role`: `personal` | `work`
- `df_vault` (derived): `ben-dotfiles` if personal, `Employee` if work

Templates and scripts read `.machine_type` / `.machine_role` / `.df_vault` to decide what
to install and render. Run `chezmoi data` to see current values. To understand any
template or script, check which of these it branches on. Notable effects:

- `headless` skips GUI config (sway/waybar/gammastep) and GUI packages
- `work` swaps Chrome→Edge, swaps git/ssh identity vault, restricts firewall differently,
  and **freezes** wallpaper/lock/login images after first apply (see next section)

## Non-obvious patterns

**Work-machine "freeze after first apply"** (`.chezmoiignore`): a `stat`-guarded ignore
block adds `.local/share/{wallpaper,lockscreen,loginscreen}.jpg` to the ignore list
*only once the file already exists* on a `work` machine. Net effect: a fresh work box
gets the repo default once, then local changes are never overwritten. Personal machines
never match the block, so they always track the repo.

**1Password is read at template-render time.** `op` must be signed in *before*
`chezmoi apply`/`init` or rendering fails. Secrets come via
`onepasswordRead "op://<vault>/<item>/<field>"`, where `<vault>` is `.df_vault`
(role-dependent). Mode is `account` (`.chezmoi.toml.tmpl`). Used in: `dot_gitconfig.tmpl`
(name/email), `private_dot_ssh/config.tmpl` (host blocks), and
`.chezmoiscripts/run_once_before_05-setup-ssh-keys.sh.tmpl` (key material). Adding any new
`onepasswordRead` means the corresponding item must exist in **both** the `ben-dotfiles`
and `Employee` vaults if the path is role-generic.

**Script execution model** (`.chezmoiscripts/`, ordered by the `NN-` numeric prefix):
- `run_before_*` / `run_after_*` — relative to applying the rest of the files
- `run_once_*` — runs once ever; re-runs only if the rendered script content changes
- `run_onchange_*` — re-runs whenever rendered content changes (e.g. package list edits
  in `run_onchange_before_01-install-packages.sh.tmpl` trigger a reinstall pass)

Provisioning is idempotent: scripts check `rpm -q` / `command -v` / `systemctl is-enabled`
before acting. Internet-fetched optional tools (Claude Code, Devbox, jj) run in subshells
and **warn-and-continue** on failure so a restricted network doesn't abort provisioning.

**Browsers + VS Code are dnf, not Flatpak** — deliberate. Flatpak sandboxing breaks host
integration (VS Code terminal/toolchains/Docker; browser native messaging). See the long
comment in `run_onchange_before_01-install-packages.sh.tmpl`.

**`.chezmoiexternal.toml`** manages fonts, zsh plugins, and the winbox binary as external
downloads with a 168h `refreshPeriod`; force a refresh with `chezmoi apply --refresh-externals`.

## Commands

There is no build/test. Validation is done with chezmoi itself:

- `chezmoi diff` — preview what `apply` would change (use this as the "test")
- `chezmoi apply -v` — render + deploy; `chezmoi apply --dry-run -v` to rehearse
- `chezmoi apply path/in/home` — apply a single target only
- `chezmoi execute-template < file.tmpl` — render one template with live data (the way to
  debug template/`onepasswordRead` logic without deploying)
- `chezmoi execute-template '{{ .machine_role }}'` — evaluate an expression
- `chezmoi data` — dump the template data (machine_type/role/df_vault)
- `chezmoi managed` / `chezmoi unmanaged` — what is / isn't tracked
- `chezmoi re-add` — pull edits made directly in `$HOME` back into source state

Fresh machine: `bootstrap.sh` (installs git/sshd, 1Password CLI + signin, chezmoi via dnf,
then `chezmoi init --apply benperiton`).

## Repo meta (chezmoiignored — not deployed to $HOME)

`bootstrap.sh`, `docs/`, and this `CLAUDE.md` are listed in `.chezmoiignore` so they live
in the repo without landing in `$HOME`. `docs/superpowers/{plans,specs}/` holds design
docs and implementation plans from the superpowers workflow; check there for the rationale
behind larger changes before reworking them.
