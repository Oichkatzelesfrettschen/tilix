# Research Sources

This folder captures upstream documentation, research notes, and validation findings used for the DUB-first refactor and Pure D backend development.

## DUB Documentation

| Document | Description |
|----------|-------------|
| [dub-build-settings.md](dub-build-settings.md) | Build settings reference |
| [dub-package-settings.md](dub-package-settings.md) | Package settings reference |
| [dub-target-types.md](dub-target-types.md) | Target types reference |
| [dub-hooks.md](dub-hooks.md) | Pre/post build hooks |
| [dub-subpackages.md](dub-subpackages.md) | Subpackage configuration |
| [dub-environment-variables.md](dub-environment-variables.md) | Environment variables |
| [dub-recipe.md](dub-recipe.md) | Recipe format reference |
| [dub-settings.md](dub-settings.md) | Settings reference |

HTML copies for traceability:
- dub-package-format.html
- dub-package-format-ref.html
- dub-package-format-upgrades.html
- dub-build-settings.html
- dub-subpackages.html

Sources:
- https://github.com/dlang/dub-docs (raw files under docs/dub-reference)
- https://dub.pm (HTML copies and redirects)

## DMD Compiler Reference

| Document | Description |
|----------|-------------|
| dmd.html | DMD switch reference |

Key switches used:
- `-w` (warnings as errors via DFLAGS)
- `-de` (deprecation as errors)

Source: https://dlang.org/dmd.html

## Feature Harvest

| Document | Description |
|----------|-------------|
| [feature-harvest.md](feature-harvest.md) | Feature inventory from other terminals |

Sources:
- Ghostty README
- Alacritty features.md
- Kitty overview

## Pure D Backend Research

| Document | Description |
|----------|-------------|
| [pure-d-packages.md](pure-d-packages.md) | Pure D package candidates |
| [gc-audit.md](gc-audit.md) | GC usage audit |

## Accessibility Research

| Document | Description |
|----------|-------------|
| [accessibility-contrast.md](accessibility-contrast.md) | WCAG contrast research |

## Validation and Testing

| Document | Description |
|----------|-------------|
| [validation-2026-01-05.md](validation-2026-01-05.md) | Validation notes |
| [xpra-crash.md](xpra-crash.md) | XPRA crash investigation |

## Notes

- These references justify the strict build requirements and checks.
- HTML copies are preserved for traceability when upstream docs move URLs.
- Feature harvest informs the Pure D backend roadmap.
