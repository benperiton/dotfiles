#!/bin/bash
set -euo pipefail

# Isolated Python venv for working with PowerPoint (.pptx) files via python-pptx.
# Kept out of the system Python, which Fedora externally-manages (PEP 668).
# Rendering pptx -> pdf/png is handled by the LibreOffice flatpak, installed in
# run_onchange_before_08-setup-gui-apps.sh.tmpl (org.libreoffice.LibreOffice).
#
# Bump PPTX_VERSION to upgrade; run_onchange re-runs this whenever the file changes.

PPTX_VERSION="1.0.2"
VENV="${HOME}/.venvs/pptx"

if [ ! -x "${VENV}/bin/python" ]; then
    echo "Creating python-pptx venv at ${VENV}"
    python3 -m venv "${VENV}"
fi

"${VENV}/bin/pip" install --quiet --upgrade "python-pptx==${PPTX_VERSION}"

echo "python-pptx $("${VENV}/bin/python" -c 'import pptx; print(pptx.__version__)') ready in ${VENV}"
