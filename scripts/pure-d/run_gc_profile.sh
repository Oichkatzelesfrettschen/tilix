#!/usr/bin/env bash
set -euo pipefail

# Build the headless tests so GC stats can be collected on exit.
DFLAGS='-w -wi' dub build --config=pure-d-tests

# Use druntime gcopt profile mode to print GC stats when the process exits.
./build/pure/tilix-pure-tests --DRT-gcopt=profile:1
