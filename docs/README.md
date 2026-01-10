# Tilix Documentation Index

This directory contains the comprehensive documentation for the Tilix terminal emulator project.

## Quick Links

- [Build Guide](BUILD_DUB.md) - How to build Tilix with DUB
- [Install Requirements](INSTALL_REQUIREMENTS.md) - Dependencies and toolchain requirements
- [Reproducible Builds](REPRODUCIBLE_BUILDS.md) - CI-ready reproducible build steps
- [Contributing](../CONTRIBUTING.md) - How to contribute to Tilix

## Documentation Structure

### 📋 [Roadmaps](roadmaps/) ([README](roadmaps/README.md))

Project planning, phase documentation, and TODO tracking.

| Document | Description |
|----------|-------------|
| [COMPREHENSIVE_ROADMAP.md](roadmaps/COMPREHENSIVE_ROADMAP.md) | Master development roadmap with phases 0-6 |
| [PURE_D_ROADMAP.md](roadmaps/PURE_D_ROADMAP.md) | Pure D backend implementation roadmap |
| [TODO.md](roadmaps/TODO.md) | DUB-first TODO list with task tracking |
| [PHASE1_COMPLETE.md](roadmaps/PHASE1_COMPLETE.md) | Phase 1 completion status |
| [PHASE1_VTE_SPECIFIC_OPS.md](roadmaps/PHASE1_VTE_SPECIFIC_OPS.md) | VTE-specific operations analysis |
| [PHASE5_DEPLOYMENT_CHECKLIST.md](roadmaps/PHASE5_DEPLOYMENT_CHECKLIST.md) | Phase 5 deployment checklist |
| [PHASE5_PERFORMANCE_BASELINE.md](roadmaps/PHASE5_PERFORMANCE_BASELINE.md) | Performance baseline documentation |

### 🔍 [Audits](audits/) ([README](audits/README.md))

Code audits, technical debt analysis, and quality reports.

| Document | Description |
|----------|-------------|
| [ARCHITECTURAL_AUDIT.md](audits/ARCHITECTURAL_AUDIT.md) | Architectural schizophrenia audit (critical) |
| [TECH_DEBT_AUDIT.md](audits/TECH_DEBT_AUDIT.md) | Technical debt inventory (22 items) |
| [TERMINAL_VTE_AUDIT.md](audits/TERMINAL_VTE_AUDIT.md) | VTE integration audit |
| [CONFIG_AUDIT.md](audits/CONFIG_AUDIT.md) | Configuration system audit |
| [LENGTH_SUBTRACTION_AUDIT.md](audits/LENGTH_SUBTRACTION_AUDIT.md) | Length subtraction security audit |
| [VIRTUAL_CONSTRUCTOR_CALLS_AUDIT.md](audits/VIRTUAL_CONSTRUCTOR_CALLS_AUDIT.md) | Virtual constructor calls audit |
| [TODO-FIXME-AUDIT.md](audits/TODO-FIXME-AUDIT.md) | TODO/FIXME inventory |
| [TODO-FIXME-SUMMARY.md](audits/TODO-FIXME-SUMMARY.md) | TODO/FIXME summary |

### 🏗️ [Design](design/) ([README](design/README.md))

Architecture design documents and technical specifications.

| Document | Description |
|----------|-------------|
| [PHASE5_ARCHITECTURE.md](design/PHASE5_ARCHITECTURE.md) | Phase 5 architecture design |
| [PHASE5_STATE_MANAGER_DESIGN.md](design/PHASE5_STATE_MANAGER_DESIGN.md) | State manager design |
| [PHASE5_TO_PHASE6_MIGRATION.md](design/PHASE5_TO_PHASE6_MIGRATION.md) | Migration path from Phase 5 to 6 |
| [PHASE6_PURE_D_ARCHITECTURE.md](design/PHASE6_PURE_D_ARCHITECTURE.md) | Pure D architecture design |
| [FORMAL_METHODS_EXPANSION_DESIGN.md](design/FORMAL_METHODS_EXPANSION_DESIGN.md) | TLA+ and Z3 integration design |
| [VIRTUAL_CALLS_REFACTORING_DESIGN.md](design/VIRTUAL_CALLS_REFACTORING_DESIGN.md) | Virtual calls refactoring plan |

### 📊 [Analysis](analysis/) ([README](analysis/README.md))

Development analysis and research findings.

| Document | Description |
|----------|-------------|
| [TILIX_DEVELOPMENT_ANALYSIS_2026.md](analysis/TILIX_DEVELOPMENT_ANALYSIS_2026.md) | Comprehensive development analysis |

### 🏛️ [Architecture](architecture/) ([README](architecture/README.md))

Backend interface maps and architectural documentation.

| Document | Description |
|----------|-------------|
| [backend-interface-map.md](architecture/backend-interface-map.md) | Backend abstraction interface map |

### 💡 [Pure D Backend](pure-d/) ([README](pure-d/README.md))

Pure D backend implementation documentation.

| Document | Description |
|----------|-------------|
| [accessibility.md](pure-d/accessibility.md) | Accessibility features |
| [betterc-boundary.md](pure-d/betterc-boundary.md) | BetterC boundary definition |
| [config.md](pure-d/config.md) | Configuration system |
| [crash-recovery.md](pure-d/crash-recovery.md) | Crash recovery mechanism |
| [grid-ndslice.md](pure-d/grid-ndslice.md) | Grid and ndslice implementation |
| [ime-keyrepeat.md](pure-d/ime-keyrepeat.md) | IME and key repeat handling |
| [input-mapping.md](pure-d/input-mapping.md) | Input mapping system |
| [instance-data-layout.md](pure-d/instance-data-layout.md) | Instance data layout |
| [ipc.md](pure-d/ipc.md) | IPC protocol documentation |
| [nogc-audit.md](pure-d/nogc-audit.md) | @nogc audit |
| [packaging.md](pure-d/packaging.md) | Packaging guidelines |
| [perf-harness.md](pure-d/perf-harness.md) | Performance harness |
| [profiling.md](pure-d/profiling.md) | Profiling guide |
| [quake-mode.md](pure-d/quake-mode.md) | Quake mode implementation |
| [scrollback-buffer.md](pure-d/scrollback-buffer.md) | Scrollback buffer design |
| [theme-presets.md](pure-d/theme-presets.md) | Theme preset system |
| [threading-model.md](pure-d/threading-model.md) | Threading model |

### 📚 [Research](research/) ([README](research/README.md))

Research notes on external documentation and technologies.

| Document | Description |
|----------|-------------|
| [README.md](research/README.md) | Research overview |
| [dub-build-settings.md](research/dub-build-settings.md) | DUB build settings reference |
| [dub-environment-variables.md](research/dub-environment-variables.md) | DUB environment variables |
| [dub-hooks.md](research/dub-hooks.md) | DUB hooks documentation |
| [dub-package-settings.md](research/dub-package-settings.md) | DUB package settings |
| [dub-recipe.md](research/dub-recipe.md) | DUB recipe format |
| [dub-settings.md](research/dub-settings.md) | DUB settings reference |
| [dub-subpackages.md](research/dub-subpackages.md) | DUB subpackages |
| [dub-target-types.md](research/dub-target-types.md) | DUB target types |
| [feature-harvest.md](research/feature-harvest.md) | Feature harvest from other terminals |
| [gc-audit.md](research/gc-audit.md) | GC audit |
| [pure-d-packages.md](research/pure-d-packages.md) | Pure D packages reference |
| [accessibility-contrast.md](research/accessibility-contrast.md) | Accessibility contrast research |
| [validation-2026-01-05.md](research/validation-2026-01-05.md) | Validation notes |
| [xpra-crash.md](research/xpra-crash.md) | XPRA crash analysis |

### 📖 [Terminal Analysis](term_analysis/) ([README](term_analysis/README.md))

Analysis of other terminal emulators.

| Document | Description |
|----------|-------------|
| [scan-summary.md](term_analysis/scan-summary.md) | Build markers and extension counts |
| [doc-index.md](term_analysis/doc-index.md) | Documentation index per repository |
| [term-analysis.md](term_analysis/term-analysis.md) | Analysis overview |

### 📝 [Guides](guides/) ([README](guides/README.md))

User and developer guides.

*Coming soon: User guides and how-to documentation.*

## Build System

Tilix uses **DUB** as the primary build system with **Meson** as a packaging fallback.

### Quick Build

```bash
# Install dependencies (Arch/CachyOS)
sudo pacman -S --needed dmd dtools dub ldc gcc-d gtk3 vte3

# Build with DUB
DFLAGS="-w" dub build --build=release

# Install
sudo ./install.sh
```

For detailed build instructions, see [BUILD_DUB.md](BUILD_DUB.md).

## Project Status

- **Phase 0-4**: Complete (backend abstraction, IO thread, state management)
- **Phase 5**: In progress (process indicators, tab previews)
- **Phase 6**: Planned (vi-mode, hints system)

See [COMPREHENSIVE_ROADMAP.md](roadmaps/COMPREHENSIVE_ROADMAP.md) for the full roadmap.

## Related Documentation

- [Root README](../README.md) - Project overview
- [Contributing](../CONTRIBUTING.md) - Contribution guidelines
- [Credits](../CREDITS.md) - Project credits
- [gemini.md](../gemini.md) - Gemini audit and roadmap summary
- [Verification](../verification/README.md) - Formal verification pipeline
