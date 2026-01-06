# GC Audit Notes (Pure D)

Scope: render loop + parser hot path. Goal is to keep steady-state frames allocation-free.

Current mitigations
- Renderer buffers (`_instances`, `_lineBuffer`, `_shapeBuffer`) are preallocated via `prepareBuffers` on resize, and render now early-returns when buffers are undersized.
- Parser worker chunk buffer is reused per loop.
- HarfBuzz shaping is `@nogc` and refuses to grow the glyph buffer in the hot path.
- Selection hit testing and cursor contrast helpers are now `@nogc`.
- `pure-d-nogc` build config enables `PURE_D_STRICT_NOGC` and uses non-alloc glyph lookups.
- `ByteRing` accessors and read/write paths are now `@nogc` to document parser safety.
- Search highlight ranges are cached and rebuilt only when scrollback offset or search generation changes.

Remaining GC risks
- `CellRenderer.render` still uses `FontAtlas.getGlyph` / `getGlyphByIndex`, which can allocate on cache miss.
- `attributesToColors` cannot be marked `@nogc` because arsd `TextAttributes` accessors are not annotated.
- `PureDEmulator.feedData` and `arsd.terminalemulator` internals are not `@nogc`-annotated; parser thread may allocate.
- Search helpers (`findInScrollback`, `findInFrame`) build result arrays via `~=`; not in the render loop, but will allocate during search.
- Title updates in the main loop format strings periodically and allocate outside the strict render path.

Mitigation options
- Move all buffer growth into explicit resize/setup phases; guard render with early-return if buffers are undersized.
- Introduce `@nogc` wrappers for glyph cache lookups (`tryGetGlyph`) and prime caches off the render thread.
- Patch or fork the emulator to use preallocated buffers if a strict `@nogc` parse loop is required.
- Add build-time `@nogc` annotations incrementally to isolate non-compliant code.
