# Tilix DUB-First TODO

## Build and Install
- [x] Add DUB preBuild resource preparation
- [x] Stage resources and metadata in build/dub
- [x] Switch install.sh to staged outputs and prefix-safe D-Bus service
- [ ] Validate install/uninstall via DUB configs on a clean system
- [ ] Add developer run targets (debug + trace) with explicit DUB commands
- [ ] Reconcile DUB warning about warningsAsErrors/buildRequirements

## Documentation
- [x] Capture DUB and DMD docs in docs/research
- [x] Expand install requirements for appstream/po4a tooling
- [ ] Add a dedicated build architecture doc
- [ ] Record reproducible build steps and CI-ready script

## Verification and Benchmarking
- [x] Keep layout fuzz tests in unittests
- [x] Add bench-scroll DUB target
- [ ] Add a layout verification runner with metrics output
- [ ] Define baseline performance metrics and regression thresholds

## Architecture and Feature Harvest
- [ ] Draft backend interface boundaries (GTK3/GTK4/Qt/KMS)
- [ ] Identify candidate features from ghostty/alacritty/kitty
- [ ] Prototype at least one backend abstraction layer
