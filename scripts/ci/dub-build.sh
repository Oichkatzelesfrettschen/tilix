#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

cd "$ROOT_DIR"

: "${DFLAGS:=-w}"
export DUBPATH="$ROOT_DIR/vendor${DUBPATH:+:$DUBPATH}"

printf '%s\n' "==> DUB build (release)"
DFLAGS="$DFLAGS" dub build --build=release --force

printf '%s\n' "==> DUB test"
DFLAGS="$DFLAGS" dub test --force

if [ "${TILIX_CI_PURE_D:-0}" = "1" ]; then
    printf '%s\n' "==> DUB build (pure-d)"
    DFLAGS="$DFLAGS" dub build --build=release --config=pure-d --force
fi
