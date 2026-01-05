#!/usr/bin/env sh
set -eu

if [ "${DUB_TARGET_TYPE:-}" = "none" ]; then
    exit 0
fi

if [ "${TILIX_ALLOW_WARNINGS:-}" = "1" ]; then
    exit 0
fi

case " ${DFLAGS:-} " in
    *" -w "*) ;;
    *)
        echo "Strict build requires DFLAGS to include -w (treat warnings as errors)." >&2
        echo "Example: DFLAGS='-w' dub build --build=release" >&2
        echo "Set TILIX_ALLOW_WARNINGS=1 to bypass." >&2
        exit 1
        ;;
esac
