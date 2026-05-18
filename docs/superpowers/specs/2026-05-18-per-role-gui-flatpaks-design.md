# Per-role GUI Flatpaks — design

**Date:** 2026-05-18
**Status:** Approved

## Problem

`run_onchange_before_08-setup-gui-apps.sh.tmpl` installs GUI apps via
Flatpak/Flathub from a single flat `FLATPAKS=(...)` list, gated only by
`{{ ne .machine_type "headless" }}`. The list is **not role-aware**, so every
GUI machine — personal *and* work — gets the same apps. Two apps should be
personal-only, and the work machine needs two apps it does not get today.

## Design

Split the flat `FLATPAKS` array into a shared list plus a `machine_role`
branch, mirroring the `ROLE_PACKAGES` pattern already used in
`run_onchange_before_01-install-packages.sh.tmpl`.

- **`COMMON_FLATPAKS`** (both roles, unchanged set):
  `com.google.Chrome`, `org.gimp.GIMP`, `org.inkscape.Inkscape`,
  `com.sublimetext.three`, `org.libreoffice.LibreOffice`,
  `org.filezillaproject.Filezilla`, `com.usebruno.Bruno`,
  `org.remmina.Remmina`, `com.github.tchx84.Flatseal`
- **personal branch** adds: `net.cozic.joplin_desktop`,
  `io.github.martchus.syncthingtray`
- **work branch** adds: `io.dbeaver.DBeaverCommunity`, `com.microsoft.Edge`
- Merge into `FLATPAKS`:
  `FLATPAKS=( "${COMMON_FLATPAKS[@]}" "${ROLE_FLATPAKS[@]}" )`

Everything else in the script is unchanged: the `ne .machine_type "headless"`
gate, the Flathub remote-add, the missing-detection loop, and the
`sudo flatpak install -y flathub` call.

Net effect by machine:

| machine | change |
| --- | --- |
| personal GUI | unchanged (still gets Joplin + Syncthing Tray + common) |
| work GUI | loses Joplin + Syncthing Tray; gains DBeaver + Edge |
| any headless | unchanged (script still no-ops) |

## VS Code (explicitly unchanged)

VS Code stays as the native `code` package via the Microsoft dnf repo in
`run_onchange_before_01-install-packages.sh.tmpl`'s `GUI_PACKAGES` (which is
role-agnostic, so it already installs on both personal and work GUI
machines). It is deliberately **not** moved to Flatpak: the Flatpak build is
sandboxed and degrades the integrated terminal, host toolchain/Docker access,
and many extensions. No change to `01-install-packages.sh.tmpl`.

## Out of scope

- No change to `01-install-packages.sh.tmpl` (dnf packages, including `code`).
- No change to the common Flatpak set or the Sublime Text 3 ID
  (`com.sublimetext.three`) — preserved as-is.
- DBeaver is the free Community edition (`io.dbeaver.DBeaverCommunity`).
