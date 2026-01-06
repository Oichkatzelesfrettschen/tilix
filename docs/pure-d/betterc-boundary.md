# BetterC Boundary (Pure D)

This document defines which subsystems must be BetterC-compatible for
latency-critical paths and which can remain full D.

## BetterC-required (hot path)
- Render loop and frame pacing (no GC, no exceptions).
- PTY byte ingestion + SIMD pre-scan.
- Instance buffer packing for renderer.
- Glyph atlas upload hot paths.
- Input translation for key events and mouse reporting.

## Full D allowed (control plane)
- Config loading/saving (mir-ion).
- Theme parsing/importers.
- IPC server/client (capnproto-dlang).
- Session/tab management and layout state.
- Logging, metrics, and diagnostics.

## Enforcement strategy
- Mark hot-path functions `@nogc nothrow` and run `-w` builds.
- Add a render loop unit test to assert zero allocations.
- Prefer plain structs + slices over classes in hot-path modules.

## Open questions
- Whether to build selected modules with `-betterC` or rely on `@nogc` only.
- How to isolate GC usage in background threads without affecting render loop.
