# Pure D @nogc Audit

Status:
- `pure-d-nogc` build config compiles and uses `PURE_D_STRICT_NOGC` gates.
- `scripts/pure-d/run_test_matrix.sh` includes `pure-d-nogc` with `-w -wi`.
- Renderer has `buffersReady()` `@nogc` guard; `prepareBuffers()` is called on
  layout changes (see `pured/main.d`).
- Strict `@nogc` path uses `tryGetGlyph*` to avoid atlas allocations in the
  render loop (see `pured/renderer.d`).
- `arsd.terminalemulator.TextAttributes` accessors are annotated `@nogc`
  to support `attributesToColors` in the render path.

Known allocation risks (hot paths):
- `Renderer.render()` is not annotated `@nogc` yet; it relies on dynamic arrays
  (`_instances`, `_lineBuffer`, `_shapeBuffer`) that can resize if
  `prepareBuffers()` is not called for new sizes.
- `TextShaper.shapeLine()` can allocate shaping buffers.
- Search/hyperlink caches in `pured/main.d` resize `_searchRanges`,
  `_hyperlinks`, and `_hyperlinkScratch` when results exceed capacity.

Current mitigations:
- `Renderer.buffersReady()` aborts rendering if buffers are not pre-sized.
- `prepareBuffers()` pre-sizes renderer buffers based on max viewport dims.
- Search/hyperlink buffers are pre-sized on viewport updates, and strict
  `@nogc` mode skips growth in the hyperlink scanner.

Next steps:
- Add `@nogc` annotations to `Renderer.render()` and helper hot paths once
  buffers are strictly pre-sized.
- Preallocate `_searchRanges`/`_hyperlinks` per viewport rows/cols and enforce
  capacity checks in strict `@nogc` mode.
- Audit `TextShaper` and consider a no-shaping fast path or preallocated
  shaping buffers.
- Add a build step that asserts `dub build --config=pure-d-nogc` with `-w -wi`.
