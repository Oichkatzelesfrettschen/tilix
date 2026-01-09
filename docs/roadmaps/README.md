# Tilix Roadmaps

This directory contains development roadmaps, phase documentation, and TODO tracking.

## Master Roadmap

| Document | Description |
|----------|-------------|
| [COMPREHENSIVE_ROADMAP.md](COMPREHENSIVE_ROADMAP.md) | Master development roadmap (Phases 0-6) |
| [PURE_D_ROADMAP.md](PURE_D_ROADMAP.md) | Pure D backend implementation roadmap |
| [TODO.md](TODO.md) | DUB-first TODO list with task tracking |

## Phase Documentation

### Completed Phases

| Document | Status | Description |
|----------|--------|-------------|
| [PHASE1_COMPLETE.md](PHASE1_COMPLETE.md) | ✅ Complete | Phase 1 completion status |
| [PHASE1_VTE_SPECIFIC_OPS.md](PHASE1_VTE_SPECIFIC_OPS.md) | ✅ Complete | VTE-specific operations analysis |

### Active/Planned Phases

| Document | Status | Description |
|----------|--------|-------------|
| [PHASE5_DEPLOYMENT_CHECKLIST.md](PHASE5_DEPLOYMENT_CHECKLIST.md) | 🔄 In Progress | Phase 5 deployment checklist |
| [PHASE5_PERFORMANCE_BASELINE.md](PHASE5_PERFORMANCE_BASELINE.md) | 🔄 In Progress | Performance baseline metrics |

## Project Timeline

### Phase Overview

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 0 | Critical blockers (backend abstraction, IOThread, state) | ⏳ Blocked |
| Phase 1 | DUB-first build parity | ✅ Complete |
| Phase 2 | Install/uninstall workflows | ✅ Complete |
| Phase 3 | Backend boundaries and benchmarks | ✅ Complete |
| Phase 4 | Feature harvest from other terminals | ✅ Complete |
| Phase 5 | Process indicators, tab previews | 🔄 In Progress |
| Phase 6 | Vi-mode, hints system | 📋 Planned |

### Blocking Dependencies

```
Phase 0.1 (RenderingTerminal) ← CRITICAL BLOCKER
  ├─→ Phase 0.2 (IOThread integration)
  ├─→ Phase 1.1 (Remove VTE imports)
  └─→ Phase 1.2 (Backend switching)

Phase 0.3 (State consolidation) ← CRITICAL BLOCKER
  └─→ Phase 0.2 (IOThread needs unified state)

Phase 5 ← Blocked by Phase 0
Phase 6 ← Blocked by Phase 5
```

## Estimated Timeline

- **Phase 0**: 2-3 weeks
- **Phase 5**: 2-3 weeks  
- **Phase 6**: 6-10 weeks
- **Total**: ~4 months

## Related Documentation

- [Audits](../audits/) - Issues to resolve before proceeding
- [Design](../design/) - Architecture specifications
- [CONTRIBUTING.md](../../CONTRIBUTING.md) - Contribution guidelines
