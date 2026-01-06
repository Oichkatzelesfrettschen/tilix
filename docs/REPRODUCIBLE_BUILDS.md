# Reproducible Builds (DUB)

This guide records the exact commands used to build and test Tilix with
warnings treated as errors. It assumes the packages in
`docs/INSTALL_REQUIREMENTS.md` are installed.

## Environment
- DMD 2.111.0
- LDC 1.41.0
- DUB 1.40.0

## Local dependency overrides
This repo vendors a patched `arsd-official` to silence dependency warnings.
Point DUB at the local package directory before building:

```
export DUBPATH="$PWD/vendor${DUBPATH:+:$DUBPATH}"
```

## Build (GTK/VTE)
```
export DFLAGS="-w"
dub build --build=release --force
```

## Tests
```
export DFLAGS="-w"
dub test --force
```

## Pure D backend (optional)
```
export DFLAGS="-w"
dub build --build=release --config=pure-d --force
```

## Pure D backend (LTO, LDC only)
```
export DFLAGS="-w"
dub build --build=pure-lto --config=pure-d --force
```
## CI helper
```
scripts/ci/dub-build.sh
TILIX_CI_PURE_D=1 scripts/ci/dub-build.sh
```

## Known warnings to track
- arsd-official emits deprecation warnings on DMD 2.111.0.
- DUB warns that arsd-official subpackages do not define import paths.

These are dependency-level warnings and should be tracked for upstream fixes
or mitigated via version updates and patches.
