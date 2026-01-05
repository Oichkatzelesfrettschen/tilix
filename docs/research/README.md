# Research Sources

This folder captures upstream documentation used for the DUB-first refactor.

## DUB
- Build settings: docs/research/dub-build-settings.md
- Package settings: docs/research/dub-package-settings.md
- Target types: docs/research/dub-target-types.md
- Hooks: docs/research/dub-hooks.md
- Sub-packages: docs/research/dub-subpackages.md
- Package format redirects: docs/research/dub-package-format.html
- Package format upgrades: docs/research/dub-package-format-upgrades.html

Sources:
- https://github.com/dlang/dub-docs (raw files under docs/dub-reference)
- https://dub.pm (HTML copies and redirects)

## DMD compiler flags
- DMD switch reference: docs/research/dmd.html
- Key switches used: -w (warnings as errors via DUB buildRequirements) and -de

Source:
- https://dlang.org/dmd.html

## Notes
- These references justify the buildRequirements added to dub.json.
- The HTML copies are preserved for traceability when the docs move URLs.
