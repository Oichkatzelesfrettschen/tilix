# Tilix Design Documents

This directory contains architecture design documents and technical specifications.

## Design Documents

### Phase 5 & 6 Architecture

| Document | Status | Description |
|----------|--------|-------------|
| [PHASE5_ARCHITECTURE.md](PHASE5_ARCHITECTURE.md) | Active | Phase 5 architecture design |
| [PHASE5_STATE_MANAGER_DESIGN.md](PHASE5_STATE_MANAGER_DESIGN.md) | Active | Unified state manager design |
| [PHASE5_TO_PHASE6_MIGRATION.md](PHASE5_TO_PHASE6_MIGRATION.md) | Planned | Migration path from Phase 5 to 6 |
| [PHASE6_PURE_D_ARCHITECTURE.md](PHASE6_PURE_D_ARCHITECTURE.md) | Planned | Pure D architecture for vi-mode/hints |

### Refactoring Designs

| Document | Status | Description |
|----------|--------|-------------|
| [VIRTUAL_CALLS_REFACTORING_DESIGN.md](VIRTUAL_CALLS_REFACTORING_DESIGN.md) | Complete | Virtual constructor call refactoring |
| [FORMAL_METHODS_EXPANSION_DESIGN.md](FORMAL_METHODS_EXPANSION_DESIGN.md) | Active | TLA+ and Z3 integration design |

## Design Philosophy

### Backend Abstraction

The core architectural goal is to separate terminal rendering from VTE dependencies:

1. **IRenderBackend** - Interface for rendering backends (VTE3, OpenGL)
2. **IRenderingContainer** - Widget abstraction for embedding
3. **UnifiedTerminalState** - Single source of truth for terminal state

See [PHASE5_ARCHITECTURE.md](PHASE5_ARCHITECTURE.md) for details.

### Formal Verification

Tilix uses formal methods for critical algorithms:

- **Coq** → Layout engine verification
- **TLA+** → Concurrency modeling
- **Z3** → Constraint satisfaction

See [FORMAL_METHODS_EXPANSION_DESIGN.md](FORMAL_METHODS_EXPANSION_DESIGN.md) for details.

## Related Documentation

- [Audits](../audits/) - Code audits identifying issues to fix
- [Roadmaps](../roadmaps/) - Development roadmaps
- [Architecture](../architecture/) - Backend interface maps
- [Verification](../../verification/) - Formal verification specs
