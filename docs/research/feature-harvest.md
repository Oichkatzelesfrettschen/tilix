# Feature Harvest (Ghostty, Alacritty, Kitty)

## Scope
This document captures a first-pass feature inventory from three terminal projects
to inform a backend-agnostic D interface map. It is not exhaustive; it is a
source-linked starting point for deeper validation and port planning.

## Sources
- Ghostty README (local): /home/eirikr/Github/ghostty/README.md
- Alacritty features docs (remote): https://raw.githubusercontent.com/alacritty/alacritty/master/docs/features.md
- Kitty overview docs (remote): https://sw.kovidgoyal.net/kitty/overview/

## Extracted Features
### Ghostty (from README)
- Standards compliance focus and xterm audit-driven behavior.
- Multi-renderer architecture (OpenGL on Linux, Metal on macOS).
- Dedicated IO thread for low-jitter throughput under heavy load.
- Multi-window, tabbing, and splits.
- Native platform experiences (SwiftUI on macOS, GTK on Linux/FreeBSD).
- libghostty-vt as a cross-platform embeddable terminal core.
- Built-in crash reports saved locally (opt-in to upload).
### Alacritty (from docs/features.md)
- GPU-accelerated OpenGL renderer.
- Vi mode for scrollback navigation with configurable motions.
- Search (normal and vi) with forward/backward traversal.
- Hints: regex detection with actions (keyboard or mouse).
- Selection expansion modes (semantic, line, block).
- URL opening with modifier and mouse click.
- Multi-window via IPC (alacritty msg create-window).
- Config file discovery across standard paths.

### Kitty (from overview docs)
- OpenGL-based renderer without a heavy UI toolkit dependency.
- Keyboard-first UX with full mouse support.
- Tabs and windows with multiple layouts (grid, splits, tall, etc).
- Kittens (scriptable extensions) plus watcher hooks.
- Remote control (including over SSH) for tabs, layout, fonts, colors.
- Session files and startup sessions.
- Scrollback integration with pager and piping to new windows/tabs.
- Shell integration for prompt navigation and output capture.

## Testable Hypotheses (Initial)
- Ghostty uses OpenGL on Linux and Metal on macOS as documented; verify in README
  and renderer code under ghostty/src and ghostty/src/apprt.
- Ghostty IO thread reduces jitter; verify in IO worker implementation and any
  benchmark notes.
- libghostty-vt provides a C API intended for embedding; verify headers in
  ghostty/include and libghostty-vt build targets.
- Alacritty vi mode, search, and hints match docs; verify config and source.
- Alacritty multi-window is IPC-backed; verify alacritty msg implementation.
- Kitty uses OpenGL and avoids heavyweight toolkits; verify overview docs and
  renderer source.
- Kitty kittens framework and remote control are core capabilities; verify docs
  and command entrypoints.
- Kitty scrollback pager integration exists; verify docs and config options.
## Candidate Ports (Early)
- Renderer abstraction with GPU backend selection (OpenGL now, Vulkan later).
- Scrollback search with vi-mode navigation and hint system.
- IPC or remote control for window, tab, and layout management.
- Scriptable extensions (kittens-like) via a D plugin API.
- Crash reporting and structured diagnostics for reproducibility.
- Session files and startup layouts.

## Feature Matrix (Draft)
| Feature | Source | Proposed D Module |
| --- | --- | --- |
| Multi-window, tabs, splits, layouts | Ghostty, Kitty | terminal.ui.layout |
| Vi-mode scrollback navigation | Alacritty | terminal.core.scrollback |
| Search (normal and vi) | Alacritty, Kitty | terminal.core.search |
| Hints and URL actions | Alacritty, Kitty | terminal.core.hints |
| Renderer abstraction (GPU/CPU) | Ghostty, Alacritty, Kitty | terminal.render |
| Remote control and IPC | Kitty, Alacritty | terminal.ipc |
| Crash reporting | Ghostty | terminal.diagnostics |
| Scriptable extensions | Kitty | terminal.extensions |
