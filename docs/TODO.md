# Tilix DUB-First TODO

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
- [ ] Create CI-ready build/test script for DUB path
- [ ] Decide Meson deprecation window and record criteria

## Toolchain and Dependencies (CachyOS)
- [x] Update install requirements for appstream/po4a/python tooling
- [x] Verify pacman package names and versions for D toolchain
- [ ] Record minimum DMD/LDC versions and compiler flags
- [ ] Add optional sanitizers and debug flags guidance
- [ ] Document GL/Vulkan optional stacks and validation steps

## Documentation and Research
- [x] Capture DUB and DMD docs in docs/research
- [x] Add backend architecture map (docs/architecture/backend-interface-map.md)
- [x] Add feature harvest notes (ghostty, alacritty, kitty)
- [x] Document xpra crash analysis and mitigation
- [x] Update gemini.md with latest audit and research notes
- [ ] Add dedicated build architecture doc (DUB pipeline + resources)
- [ ] Record reproducible build steps and CI-ready script
- [x] Add term_analysis overview doc with repo list and scope

## TODO/FIXME Audit
- [x] Generate TODO/FIXME inventory (docs/TODO-FIXME-AUDIT.md)
- [ ] Classify TODO/FIXME items by subsystem and severity
- [ ] Convert actionable TODO/FIXME items into tasks with owners
- [ ] Remove obsolete or invalid TODOs

## Verification and Benchmarking
- [x] Keep layout fuzz tests in unittests
- [x] Add bench-scroll DUB target
- [ ] Add layout verification runner with metrics output
- [ ] Define baseline performance metrics and regression thresholds
- [ ] Add performance harness for scrollback, render, IO

## Architecture and Feature Harvest
- [x] Draft backend interface boundaries (GTK3/GTK4/Qt/KMS)
- [x] Identify candidate features from ghostty/alacritty/kitty
- [x] Produce feature matrix mapped to proposed D modules
- [ ] Prototype a minimal backend abstraction layer
- [ ] Implement no-op backends for testing
- [ ] Define VTE interop layer or deprecation plan
