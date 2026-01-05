# Contributing to Tilix

## Code Quality Policy

### Warnings as Errors

All builds MUST pass with zero warnings. This is enforced via:

- **DUB**: `DFLAGS='-w' dub build`
- **Meson**: `-w` flag is default in `meson.build`

The `scripts/dub/strict-check.sh` script enforces this for DUB builds.

To bypass (for local debugging only):
```sh
TILIX_ALLOW_WARNINGS=1 dub build
```

### Why This Matters

1. Warnings often indicate real bugs (unused variables, type mismatches)
2. Warning accumulation leads to "warning blindness"
3. Clean builds enable static analysis tools
4. New warnings are immediately visible and actionable

### Build Commands

```sh
# DUB (strict mode)
DFLAGS='-w' dub build --build=release

# Meson (strict by default)
meson setup builddir
meson compile -C builddir

# Run tests
meson test -C builddir
```

## Pull Request Guidelines

1. Ensure zero warnings in both DUB and Meson builds
2. Run unit tests before submitting
3. Follow existing code style (D conventions)
4. Keep PRs focused on a single concern

## Reporting Issues

Please include:
- Tilix version (`tilix --version`)
- Distribution and version
- Steps to reproduce
- Expected vs actual behavior
