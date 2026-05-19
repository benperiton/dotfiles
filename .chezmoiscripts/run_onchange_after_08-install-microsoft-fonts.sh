#!/bin/bash
set -euo pipefail

# Genuine Microsoft fonts, three delivery routes by source type:
#
#   core (Arial, Times New Roman, Courier New, Verdana, Georgia,
#   Trebuchet, Comic Sans, Impact, Andale Mono, Webdings):
#     SourceForge "corefonts", Microsoft's redistributable "Core fonts
#     for the Web". Shipped as self-extracting CAB .exe files, so they
#     need cabextract (added to BASE_PACKAGES in
#     run_onchange_before_01-install-packages.sh.tmpl).
#
#   ClearType/Office (Calibri, Cambria + Cambria Math, Candara,
#   Consolas, Constantia, Corbel), Segoe UI, and symbol fonts:
#     loose TTFs from the lexics.github.io mirror, no extraction.
#
# Aptos is deliberately NOT here: it is a stable upstream zip and is
# handled as a chezmoi external in .chezmoiexternal.toml instead.
#
# fc-cache is deliberately NOT run here. run_after_50-refresh-fonts.sh
# rebuilds the font cache after every font-producing step.
#
# Per the repo convention, each network tier runs in its own subshell
# and warns-and-continues on failure so a restricted/offline network
# does not abort provisioning. Re-runs only when this file changes
# (run_onchange); curl overwrites in place so re-runs are safe.

dest="${HOME}/.local/share/fonts/microsoft"
mkdir -p "${dest}"/{core,clearType,segoeUI,symbols}

CURL=(curl -fsSL --connect-timeout 15 --max-time 180 --retry 3 --retry-delay 2)

# --- Core fonts: SourceForge corefonts via cabextract ---
if command -v cabextract &>/dev/null; then
    (
        set -eo pipefail
        base="https://downloads.sourceforge.net/corefonts"
        cabs=( andale32 arial32 arialb32 comic32 courie32 georgi32
               impact32 times32 trebuc32 verdan32 webdin32 )
        tmp="$(mktemp -d)"
        trap 'rm -rf "$tmp"' EXIT
        for c in "${cabs[@]}"; do
            "${CURL[@]}" -o "${tmp}/${c}.exe" "${base}/${c}.exe"
            cabextract -L -q -d "${tmp}" "${tmp}/${c}.exe"
        done
        find "${tmp}" -iname '*.ttf' -exec cp -f {} "${dest}/core/" \;
        echo "core: $(find "${dest}/core" -iname '*.ttf' | wc -l) font files"
    ) || echo "WARNING: core fonts (SourceForge corefonts) failed, skipping" >&2
else
    echo "WARNING: cabextract not found, skipping genuine core fonts" >&2
fi

# --- ClearType / Office set (lexics mirror) ---
(
    set -eo pipefail
    base="https://lexics.github.io/assets/downloads/fonts/clearTypeFonts"
    fonts=( calibri calibrib calibrii calibriz
            cambria cambriab cambriai cambriaz cambriamath
            candara candarab candarai candaraz
            consola consolab consolai consolaz
            constan constanb constani constanz
            corbel corbelb corbeli corbelz )
    for f in "${fonts[@]}"; do
        "${CURL[@]}" -o "${dest}/clearType/${f}.ttf" "${base}/${f}.ttf"
    done
    echo "clearType: ${#fonts[@]} font files"
) || echo "WARNING: ClearType/Office fonts failed, skipping" >&2

# --- Segoe UI family (lexics mirror) ---
(
    set -eo pipefail
    base="https://lexics.github.io/assets/downloads/fonts/segoeUI"
    fonts=( segoeui segoeuib segoeuii segoeuil segoeuisl segoeuiz
            seguili seguisb seguisbi seguisli )
    for f in "${fonts[@]}"; do
        "${CURL[@]}" -o "${dest}/segoeUI/${f}.ttf" "${base}/${f}.ttf"
    done
    echo "segoeUI: ${#fonts[@]} font files"
) || echo "WARNING: Segoe UI fonts failed, skipping" >&2

# --- Symbol fonts (lexics mirror): Symbol, Wingdings 1-3, MT Extra ---
(
    set -eo pipefail
    base="https://lexics.github.io/assets/downloads/fonts/other-essential-fonts"
    fonts=( mtextra symbol webdings wingding wingdng2 wingdng3 )
    for f in "${fonts[@]}"; do
        "${CURL[@]}" -o "${dest}/symbols/${f}.ttf" "${base}/${f}.ttf"
    done
    echo "symbols: ${#fonts[@]} font files"
) || echo "WARNING: symbol fonts failed, skipping" >&2

echo "Microsoft fonts staged in ${dest} (cache rebuilt by run_after_50-refresh-fonts.sh)"
