# Validation Notes (2026-01-05)

This file records primary-source checks performed during the audit.

## DUB registry checks
- arsd-official 12.1.0 listed at https://code.dlang.org/packages/arsd-official
- mir-algorithm latest listed as 3.22.4 via `dub search mir-algorithm`
- bindbc-glfw latest listed as 1.1.2 via `dub search bindbc-glfw`

## Observed build warnings
- arsd-official deprecation warnings resolved by patching `Event.set()` to
  `Event.setIfInitialized()` in a vendored copy.
- DUB importPaths warnings resolved by adding `importPaths` to arsd-official
  subpackages (core, color_base, terminalemulator).

The repo now uses `DUBPATH=$PWD/vendor` to ensure the patched package is used.
