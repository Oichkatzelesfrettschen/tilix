#!/usr/bin/env bash
set -euo pipefail

if ! command -v vttest >/dev/null 2>&1; then
  echo "vttest not found. See docs/INSTALL_REQUIREMENTS.md for install steps." >&2
  exit 1
fi

echo "Run vttest in the active terminal to validate VT behavior."
exec vttest
