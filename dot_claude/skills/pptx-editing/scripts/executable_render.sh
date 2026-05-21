#!/usr/bin/env bash
# Render a .pptx to PDF (and optionally per-slide PNGs) for visual verification.
#
# Uses the LibreOffice flatpak (org.libreoffice.LibreOffice). This is the only
# reliable .pptx renderer on this box -- headless Chrome CANNOT render .pptx.
#
# Gotchas baked in:
#   - The LO flatpak cannot see /tmp. Everything here stays under $HOME.
#   - A second soffice instance silently no-ops, so we hand LO a private,
#     throwaway profile dir (UserInstallation) per run.
#
# Usage:
#   render.sh INPUT.pptx [OUTDIR] [--png [DPI]]
#
# Examples:
#   render.sh deck.pptx                 # -> deck.pdf next to the input
#   render.sh deck.pptx ./out           # -> ./out/deck.pdf
#   render.sh deck.pptx ./out --png     # -> ./out/deck.pdf + ./out/slide-NN.png
#   render.sh deck.pptx ./out --png 200 # PNGs at 200 DPI (default 150)
set -euo pipefail

[ $# -ge 1 ] || { echo "usage: render.sh INPUT.pptx [OUTDIR] [--png [DPI]]" >&2; exit 2; }

INPUT="$1"; shift
[ -f "$INPUT" ] || { echo "render.sh: no such file: $INPUT" >&2; exit 2; }
INPUT="$(readlink -f "$INPUT")"

OUTDIR="$(dirname "$INPUT")"
WANT_PNG=0
DPI=150
while [ $# -gt 0 ]; do
  case "$1" in
    --png) WANT_PNG=1; shift; [[ "${1:-}" =~ ^[0-9]+$ ]] && { DPI="$1"; shift; } ;;
    *)     OUTDIR="$1"; shift ;;
  esac
done
mkdir -p "$OUTDIR"
OUTDIR="$(readlink -f "$OUTDIR")"

case "$INPUT" in "$HOME"/*) : ;; *) echo "render.sh: INPUT must be under \$HOME (flatpak can't see $INPUT)" >&2; exit 2 ;; esac
case "$OUTDIR" in "$HOME"/*) : ;; *) echo "render.sh: OUTDIR must be under \$HOME" >&2; exit 2 ;; esac

PROFILE="$(mktemp -d "$HOME/.cache/lo-render-XXXXXX")"
trap 'rm -rf "$PROFILE"' EXIT

flatpak run org.libreoffice.LibreOffice \
  "-env:UserInstallation=file://$PROFILE" \
  --headless --convert-to pdf --outdir "$OUTDIR" "$INPUT" >/dev/null

base="$(basename "${INPUT%.*}")"
PDF="$OUTDIR/$base.pdf"
[ -f "$PDF" ] || { echo "render.sh: LibreOffice produced no PDF" >&2; exit 1; }
echo "PDF: $PDF"

if [ "$WANT_PNG" -eq 1 ]; then
  command -v pdftoppm >/dev/null || { echo "render.sh: pdftoppm not found (install poppler-utils)" >&2; exit 1; }
  pdftoppm -png -r "$DPI" "$PDF" "$OUTDIR/slide"
  # pdftoppm names files slide-1.png, slide-01.png etc depending on page count.
  for f in "$OUTDIR"/slide-*.png; do echo "PNG: $f"; done
fi
