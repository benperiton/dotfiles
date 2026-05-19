#!/bin/bash
set -euo pipefail

# No -f: fc-cache only rescans directories whose contents changed, so this
# is a near no-op on every apply when no fonts were added or removed.
fc-cache
echo "Font cache refreshed"
