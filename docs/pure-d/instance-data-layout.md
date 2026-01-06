# Instance Data Layout (Pure D Renderer)

This document defines the per-cell instance data layout for instanced rendering.

## Goals
- Single draw call per frame via `glDrawArraysInstanced`.
- Cache-friendly CPU layout and minimal GPU bandwidth.
- Pack colors and glyph IDs into 32-bit fields where possible.

## Current layout (renderer implementation)
```
struct CellInstance {
    float x, y, w, h;      // rect in pixels
    float u0, v0, u1, v1;  // glyph UVs
    float fgR, fgG, fgB, fgA;
    float bgR, bgG, bgB, bgA;
    float glyphEnabled;   // 1.0 for glyph quad, 0.0 for background
}
```

## Instance strategy
- Each cell emits a background instance (full cell rect, glyphEnabled=0).
- Each visible glyph emits a glyph instance with its own rect and UVs.
- Both are drawn in a single `glDrawArraysInstanced` call.

## Alternatives
- Pack pos into 16-bit ints if viewport <= 4K to cut bandwidth.
- Use normalized U16 for colors if shader applies palette.
- Use a separate flag buffer if branch-heavy in shader.

## Notes
- A future optimization can re-pack colors and UVs into 16-bit fields.
- Glyph + background instances can be merged once shader supports per-fragment glyph masks.
