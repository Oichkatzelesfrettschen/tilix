# Tilix DUB-First TODO

## Phase 0-4 Status (COMPLETE - 2026-01-05)
- [x] Backend abstraction layer (IRenderBackend, VTE3, OpenGL)
- [x] Palette system (Ptyxis-compatible, 10 palettes, profile editor)
- [x] X11 bindings (XRandR refresh detection, XPresent prepared)
- [x] IO thread infrastructure (lock-free queue, message protocol)
- [x] Frame pacing (arbitrary Hz, adaptive timing)
- [x] Font atlas (atomic versioning, lock-free GPU sync)
- [x] Meson build fixes (XRandR linking, palette installation)
- [x] Both builds pass with -w (warnings as errors)

Next: Phase 5 (process indicators), Phase 6 (vi-mode), IO thread hookup

## Repo Governance and Sync
- [x] Disable upstream push URLs (block accidental PRs)
- [ ] Create upstream tracking branch notes (upstream/master)
- [ ] Merge upstream/master into origin/master (no rebase)
- [ ] Tag pre-merge snapshot in fork
- [ ] Rebase feature/dub-refactor on updated origin/master
- [ ] Merge feature/dub-refactor back to origin/master
- [ ] Document branch policy (fork-only, no upstream PRs)

## Term Analysis Harvest
- [x] Create term_analysis folder
- [x] Fork alacritty/kitty/wezterm/ghostty to user account
- [x] Mirror ptyxis from gitlab into user fork
- [x] Capture baseline metadata per repo (language, build system)
- [ ] Extract terminal core architecture notes per repo
- [ ] Extract rendering pipeline notes per repo
- [ ] Extract IPC/remote control notes per repo
- [ ] Extract config and profile systems per repo
- [ ] Extract extension/plugin systems per repo
- [ ] Record per-repo benchmark/latency claims and sources
- [ ] Map features into D module candidates with priority

## Build and Install
- [x] Add DUB preBuild resource preparation
- [x] Stage resources and metadata in build/dub
- [x] Switch install.sh to staged outputs and prefix-safe D-Bus service
- [ ] Validate install/uninstall via DUB configs on a clean system
- [ ] Add developer run targets (debug + trace) with explicit DUB commands
- [x] Reconcile DUB warning about warningsAsErrors/buildRequirements
- [x] Create CI-ready build/test script for DUB path
- [ ] Decide Meson deprecation window and record criteria

## Toolchain and Dependencies (CachyOS)
- [x] Update install requirements for appstream/po4a/python tooling
- [x] Verify pacman package names and versions for D toolchain
- [ ] Record minimum DMD/LDC versions and compiler flags
- [ ] Add optional sanitizers and debug flags guidance
- [ ] Document GL/Vulkan optional stacks and validation steps
- [x] Resolve dependency warnings (vendor arsd-official patch + importPaths)

## Documentation and Research
- [x] Capture DUB and DMD docs in docs/research
- [x] Add backend architecture map (docs/architecture/backend-interface-map.md)
- [x] Add feature harvest notes (ghostty, alacritty, kitty)
- [x] Document xpra crash analysis and mitigation
- [x] Update gemini.md with latest audit and research notes
- [x] Expand install requirements with per-module/package granularity (GTK/VTE, Pure D, OpenGL, tooling)
- [ ] Add dedicated build architecture doc (DUB pipeline + resources)
- [x] Record reproducible build steps and CI-ready script
- [x] Define BetterC boundary for Pure D hot paths (docs/pure-d/betterc-boundary.md)
- [x] Audit Pure D DUB packages and record candidates (docs/research/pure-d-packages.md)
- [x] Add term_analysis overview doc with repo list and scope

## TODO/FIXME Audit
- [x] Generate TODO/FIXME inventory (docs/TODO-FIXME-AUDIT.md)
- [x] Classify TODO/FIXME items by subsystem and severity
- [x] Convert actionable TODO/FIXME items into tasks with owners (TBD)
- [x] Remove obsolete or invalid TODOs

## Verification and Benchmarking
- [x] Keep layout fuzz tests in unittests
- [x] Add bench-scroll DUB target
- [ ] Add layout verification runner with metrics output
- [ ] Define baseline performance metrics and regression thresholds
- [ ] Add performance harness for scrollback, render, IO

## Pure D Backend Parity
- [x] Implement clipboard + PRIMARY selection for Pure D (X11/XCB + Wayland primary-selection)
- [x] Implement dynamic Unicode glyph caching in FontAtlas
- [x] Implement true-color extraction from emulator cell attributes
- [x] Implement bell handling and cursor style updates in Pure D UI
- [x] Add selection highlight config and accessibility outline cursor
- [x] Add search (selection + F3) integration
- [x] Implement scrollback buffer access in Pure D rendering path
- [x] Add lock-free triple buffer utility for renderer handoff
- [x] Wire triple buffer into Pure D render path
- [x] Move emulator parsing off render thread (use triple buffer)
- [ ] Decide how to complete or guard OpenGLContainer stubs in GTK backend

## Architecture and Feature Harvest
- [x] Draft backend interface boundaries (GTK3/GTK4/Qt/KMS)
- [x] Identify candidate features from ghostty/alacritty/kitty
- [x] Produce feature matrix mapped to proposed D modules
- [x] Prototype a minimal backend abstraction layer (Phase 0-4 complete)
- [x] Implement VTE3 and OpenGL backends with render abstraction
- [x] Define VTE interop layer (VTE3RenderBackend as compatibility fallback)
