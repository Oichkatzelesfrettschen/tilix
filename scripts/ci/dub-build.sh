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

    printf '%s\n' "==> DUB build (pure-d-nogc)"
    DFLAGS="$DFLAGS" dub build --build=release --config=pure-d-nogc --force

    printf '%s\n' "==> DUB build (pure-d-tests)"
    DFLAGS="$DFLAGS" dub build --build=release --config=pure-d-tests --force

    printf '%s\n' "==> Pure D headless tests"
    ./build/pure/tilix-pure-tests
fi

if [ "${TILIX_CI_PERF:-0}" = "1" ]; then
    printf '%s\n' "==> Pure D perf harness (build + instructions)"
    scripts/pure-d/run_perf_harness.sh
fi
