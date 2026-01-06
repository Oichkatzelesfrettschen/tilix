#!/usr/bin/env bash
set -euo pipefail

echo "Building Pure D backend..."
DFLAGS=-w dub build --config=pure-d

cat <<'EOF'

Performance Harness Steps
1) Launch the terminal: ./build/pure/tilix-pure
2) Inside the Pure D terminal, run:
   scripts/pure-d/generate_output.sh 512
3) For correctness, run:
   vttest

EOF

if ! command -v vttest >/dev/null 2>&1; then
  echo "vttest not found. See docs/INSTALL_REQUIREMENTS.md for install steps."
fi
