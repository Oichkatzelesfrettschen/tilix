# Pure D Backend Documentation

This directory contains documentation for the Pure D backend implementation, which bypasses GTK/VTE for direct OpenGL rendering with GLFW.

## Configuration

| Document | Description |
|----------|-------------|
| [config.md](config.md) | Configuration system overview |
| [config.schema.json](config.schema.json) | JSON schema for configuration validation |
| [sample-config.json](sample-config.json) | Example configuration file |

## Architecture

| Document | Description |
|----------|-------------|
| [threading-model.md](threading-model.md) | Threading model and async I/O |
| [grid-ndslice.md](grid-ndslice.md) | Grid implementation with mir.ndslice |
| [instance-data-layout.md](instance-data-layout.md) | Instance data memory layout |
| [scrollback-buffer.md](scrollback-buffer.md) | Scrollback buffer design |
| [betterc-boundary.md](betterc-boundary.md) | @betterC boundary for hot paths |
| [nogc-audit.md](nogc-audit.md) | @nogc audit for render paths |

## Features

| Document | Description |
|----------|-------------|
| [accessibility.md](accessibility.md) | Accessibility features and presets |
| [quake-mode.md](quake-mode.md) | Quake/dropdown mode implementation |
| [input-mapping.md](input-mapping.md) | Input mapping and keybindings |
| [ime-keyrepeat.md](ime-keyrepeat.md) | IME and key repeat handling |
| [crash-recovery.md](crash-recovery.md) | Crash recovery snapshots |
| [theme-presets.md](theme-presets.md) | Theme preset system |
| [ipc.md](ipc.md) | IPC protocol (Cap'n Proto) |

## Performance

| Document | Description |
|----------|-------------|
| [perf-harness.md](perf-harness.md) | Performance testing harness |
| [profiling.md](profiling.md) | Profiling guide |

## Packaging

| Document | Description |
|----------|-------------|
| [packaging.md](packaging.md) | Packaging guidelines |

## Building Pure D Backend

```bash
# Build Pure D backend
DFLAGS="-w" dub build --build=release --config=pure-d

# Build with LTO (LDC only)
DFLAGS="-w" dub build --build=pure-lto --config=pure-d

# Strict @nogc render path
DFLAGS="-w" dub build --build=release --config=pure-d-nogc

# Run headless tests
DFLAGS="-w" dub build --config=pure-d-tests
./build/pure/tilix-pure-tests
```

## Configuration Validation

```bash
# Validate config against schema
scripts/pure-d/validate_config.sh ~/.config/tilix/pure-d.json
```

## Related Documentation

- [roadmaps/PURE_D_ROADMAP.md](../roadmaps/PURE_D_ROADMAP.md) - Pure D implementation roadmap
- [design/PHASE6_PURE_D_ARCHITECTURE.md](../design/PHASE6_PURE_D_ARCHITECTURE.md) - Phase 6 architecture
- [INSTALL_REQUIREMENTS.md](../INSTALL_REQUIREMENTS.md) - Pure D dependencies (Section 4)
- [BUILD_DUB.md](../BUILD_DUB.md) - Build commands
