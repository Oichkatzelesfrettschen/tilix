#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT_DIR"

DFLAGS='-w -wi' dub build --config=pure-d
DFLAGS='-w -wi' dub build --config=pure-d-nogc
DFLAGS='-w -wi' dub run --config=pure-d-tests
