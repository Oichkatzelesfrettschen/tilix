#!/usr/bin/env bash
set -euo pipefail

echo "Building Pure D backend..."
DFLAGS="-w -wi" dub build --config=pure-d
DFLAGS="-w -wi" dub build --config=pure-d-nogc

cat <<'EOF'

Performance Harness Steps
1) Launch the terminal: ./build/pure/tilix-pure (or tilix-pure-nogc)
2) Inside the Pure D terminal, run a throughput burst:
   scripts/pure-d/generate_output.sh 512
3) For correctness, run:
   vttest
4) Optional: compare runs with hyperfine (inside the Pure D terminal):
   hyperfine --runs 5 "scripts/pure-d/generate_output.sh 512"

EOF

if ! command -v vttest >/dev/null 2>&1; then
  echo "vttest not found. See docs/INSTALL_REQUIREMENTS.md for install steps."
fi

if ! command -v hyperfine >/dev/null 2>&1; then
  echo "hyperfine not found (optional). See docs/INSTALL_REQUIREMENTS.md for install steps."
fi
