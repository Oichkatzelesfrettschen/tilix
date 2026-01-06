# Configuration Audit (2026-01-05)

This file tracks missing or mismatched configurations, modules, and settings
found during the audit.

## Build configuration gaps
- Meson requires appstreamcli at configure time; DUB treats it as optional.
- arsd-official warnings resolved by vendoring and patching (see `vendor/arsd-official`).
- Pure D config links only glfw/GL/freetype/X11; static GLFW may require
  additional X11 libs (Xrandr, Xinerama, Xcursor, Xi) depending on build.

## Install-time gaps
- Palettes were not installed in install.sh (fixed).
- install-man-pages.sh ignored PREFIX and always used /usr (fixed).

## Pure D feature gaps (code-level)
- Clipboard and PRIMARY selection not wired for Pure D.
- Unicode glyph caching and true-color extraction missing.
- Bell handling, cursor style updates, and scrollback access missing.
