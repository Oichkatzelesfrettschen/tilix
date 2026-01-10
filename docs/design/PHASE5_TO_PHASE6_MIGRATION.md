# Phase 5 to Phase 6 Migration Guide

## Overview

Phase 6 transitions from VTE3 library-based rendering to hardware-accelerated OpenGL rendering while maintaining the Phase 5 IO thread infrastructure. The architecture allows backend switching at compile-time through the `RenderingBackend` enum.

## Current State (End of Phase 5)

### Functional Capabilities
- ✅ Non-blocking PTY I/O via IO thread
- ✅ Lock-free event queue (Bell, Title, Data)
- ✅ Double-buffered state synchronization
- ✅ VTE3 rendering backend (production)
- ✅ OpenGLContainer stub (interface only)
- ✅ Signal-based frame update integration
- ✅ ANSI/DEC sequence parsing (via VTE delegation)

### Testing Infrastructure
- ✅ 20 VTParser unit tests
- ✅ 10+ integration tests (threading, queueing)
- ✅ Lock-free queue correctness tests
- ✅ ASAN build configuration

### Architecture
```
Terminal (main.d)
├── IRenderingContainer (interface)
│   ├── VTE3Container (production) ←── ACTIVE_BACKEND = VTE3
│   └── OpenGLContainer (stub) ←────── Phase 6 target
├── TerminalStateManager
├── IOThreadManager
└── Lock-free event queue
```

## Phase 6 Objectives

### Primary Goals
1. **Implement OpenGL rendering backend** (GPU-accelerated)
2. **Maintain feature parity** with VTE3 backend
3. **Achieve performance targets** (<100ms full-screen update, <16ms frame time)
4. **Support all ANSI sequences** natively (not delegating to VTE)
5. **Enable backend switching** via runtime or compile-time selection

### Secondary Goals
1. **Optimize glyph caching** (SDF or bitmap atlas)
2. **Implement sub-pixel rendering** (ClearType/FreeType)
3. **Support true-color (24-bit)** palette
4. **Implement accessibility** features (font scaling, contrast modes)

## Implementation Roadmap (Phase 6)

### Phase 6.1: OpenGL Infrastructure Setup
**Duration**: 1-2 weeks
**Files to Create**:
- `source/gx/tilix/backend/opengl/context.d` - GL context management
- `source/gx/tilix/backend/opengl/shader.d` - Shader compilation/caching
- `source/gx/tilix/backend/opengl/texture.d` - Texture/glyph management
- `source/gx/tilix/backend/opengl/geometry.d` - Quad/mesh generation

**Tasks**:
1. Initialize GTK OpenGL context with GTK GLArea widget
2. Implement vertex/fragment shader pipeline
3. Create glyph atlas with SDF or bitmap approach
4. Set up frame buffer and double-buffering at GL level
5. Implement basic quad rendering for cells

**Testing**:
- GL initialization tests
- Shader compilation/linking tests
- Context switch between backends

### Phase 6.2: Glyph Rendering
**Duration**: 2-3 weeks
**Files to Create**:
- `source/gx/tilix/backend/opengl/glyphcache.d` - Glyph storage/lookup
- `source/gx/tilix/backend/opengl/fontmanager.d` - Font loading/caching

**Tasks**:
1. Load FreeType fonts programmatically
2. Render glyphs to SDF texture (signed distance field)
3. Implement glyph cache with LRU eviction
4. Support font scaling (zoom) via texture coordinates
5. Handle kerning and ligature positioning

**Testing**:
- Glyph rendering correctness
- Cache hit rate under varying fonts
- Performance: <5ms per font change

### Phase 6.3: Cell Attributes and Colors
**Duration**: 1-2 weeks
**Files to Modify**:
- `source/gx/tilix/backend/opengl/renderer.d` - Main rendering loop
- `source/gx/tilix/backend/openglcontainer.d` - Update stub methods

**Tasks**:
1. Implement SGR attribute rendering (bold, italic, underline, etc.)
2. Render background cells with colors
3. Implement cursor rendering (block, underline, beam)
4. Support 256-color and true-color (24-bit) palettes
5. Implement selection highlight rendering

**Testing**:
- Attribute rendering correctness
- Color accuracy (sRGB vs linear gamma)
- Cursor shape switching
- Selection highlight

### Phase 6.4: Complete Feature Implementation
**Duration**: 2-3 weeks
**Tasks**:
1. Scrollback rendering (historical buffer)
2. Find/search highlight rendering
3. Performance optimization (batching, VBO reuse)
4. Memory leak detection (ASAN with GL allocation)
5. Cross-platform GL compatibility (GL 3.3+, GLES 3.0)

**Testing**:
- Comprehensive integration tests
- Performance benchmarks vs VTE3
- Memory profiling (ASAN + GL stats)

### Phase 6.5: Optimization and Polish
**Duration**: 1-2 weeks
**Tasks**:
1. Profile and optimize hot paths (perf, valgrind)
2. Implement vsync and frame pacing
3. Add accessibility features (contrast, zoom)
4. Create user documentation for backend switching
5. Performance regression testing

## Backend Switching Mechanism

### Compile-Time (Current)
```d
// source/gx/tilix/terminal/terminal.d
private immutable RenderingBackend ACTIVE_BACKEND = RenderingBackend.VTE3;

final switch (ACTIVE_BACKEND) {
    case RenderingBackend.VTE3:
        _container = new VTE3Container(vte);
        break;
    case RenderingBackend.OpenGL:
        _container = new OpenGLContainer(vte);
        break;
}
```

**Build**: Change `ACTIVE_BACKEND` and rebuild entire project.

### Runtime (Future Option)
```d
// Potential Phase 6 enhancement
class Terminal {
    private RenderingBackend _activeBackend;

    void switchBackend(RenderingBackend newBackend) {
        if (_activeBackend == newBackend) return;

        // Save state
        TerminalState savedState = _stateManager.getReadBuffer();

        // Dispose old container
        if (_container !is null) _container.dispose();

        // Create new container
        final switch (newBackend) {
            // ...
        }

        // Restore state
        _stateManager.restoreState(savedState);

        _activeBackend = newBackend;
        queueDraw();
    }
}
```

## Data Structure Changes

### New Phase 6 Structures
```d
// source/gx/tilix/backend/opengl/glyphkey.d
struct GlyphKey {
    dchar codepoint;
    PgFontDescription font;
    uint size;

    // Implement hash/equality for cache lookup
    hash_t toHash() const nothrow @safe;
    bool opEquals(ref const GlyphKey other) const nothrow @safe;
}

struct Glyph {
    uint textureIndex;
    uint atlasX, atlasY;
    uint width, height;
    int offsetX, offsetY;
    int advance;
}

// source/gx/tilix/backend/opengl/renderstate.d
struct GLRenderState {
    uint vao;  // Vertex Array Object
    uint vbo;  // Vertex Buffer Object
    uint ebo;  // Element Buffer Object
    uint glyphAtlasTexture;

    uint quadCount;
    Quad[4096] quads;  // Per-frame quad buffer
}
```

### No Changes to Phase 5 Structures
- `TerminalState` - unchanged, still used by OpenGL backend
- `IOMessage` - unchanged, still carries event data
- `LockFreeQueue` - unchanged, still manages inter-thread communication

## Performance Targets (Phase 6)

| Metric | Target | Method |
|--------|--------|--------|
| Frame time | <16ms (60 FPS) | perf timing, vsync measured |
| Full-screen redraw | <100ms | benchmark 80x24 clear |
| Glyph lookup | <1μs | cache hit rate >95% |
| Memory per cell | <16 bytes | struct size analysis |
| GPU memory (glyphs) | <50MB | atlas size + cache |
| Shader compilation | <100ms | profiling build startup |
| Resize latency | <50ms | measured from signal to render |

## Breaking Changes

### For Backend Implementers
1. **Must implement IRenderingContainer** - all 60+ methods required
2. **Must handle cell attribute rendering** - bold, italic, etc.
3. **Must support color palettes** - VTE256 and true-color
4. **Must implement scrollback** - maintain historical buffer

### For Users
- **API-compatible**: Terminal API unchanged
- **Signal-compatible**: Existing signal handlers continue to work
- **No behavior changes**: Same keybindings, same output parsing
- **Optional feature**: Backend switching is opt-in

## Testing Strategy (Phase 6)

### Unit Tests
```
source/gx/tilix/backend/opengl/tests/
├── context_test.d - GL initialization
├── shader_test.d - Shader compilation
├── glyphcache_test.d - Glyph storage/lookup
└── renderer_test.d - Rendering correctness
```

### Integration Tests
```
source/gx/tilix/backend/tests/
├── backend_switch_test.d - VTE3 ↔ OpenGL
└── feature_parity_test.d - Both backends same output
```

### Performance Tests
```
scripts/
├── benchmark_rendering.d - Frame time
└── benchmark_glyphcache.d - Glyph lookup
```

### Visual Regression Testing
1. **Screenshot comparison**: Capture same terminal output in both backends
2. **Diff analysis**: Pixel-perfect match required
3. **Color accuracy**: 24-bit color verification

## Dependency Changes

### New Libraries (Phase 6)
- **epoxy** or **bindbc-opengl**: OpenGL bindings
- **FreeType**: Already available, used for font rendering
- **GLM** (optional): Math library for matrix operations

### No Dependency Changes for Phase 5
- **gtk-d** 3.11.0: Unchanged
- **VTE** 3.11.0: Unchanged (still used for reference)

## Rollback Plan

### If Phase 6 Encounters Critical Issues
1. **Revert ACTIVE_BACKEND** to VTE3
2. **Rebuild binary**: `dub clean && DFLAGS='-w' dub build --build=release`
3. **Restore functionality**: All VTE3 code paths unmodified

### Phase 5 Stability
- Phase 5 code is stable and production-ready
- Phase 6 is additive, does not modify Phase 5 infrastructure
- Can deploy Phase 5 to production immediately
- Phase 6 can be developed in parallel on feature branch

## Timeline and Milestones

| Milestone | Phase | Duration | Status |
|-----------|-------|----------|--------|
| IO Thread Integration | 5 | 3 weeks | ✅ Complete |
| Lock-free Queues | 5 | 1 week | ✅ Complete |
| VTE3 Abstraction | 5 | 2 weeks | ✅ Complete |
| Testing & Integration | 5 | 2 weeks | ✅ Complete |
| **OpenGL Foundation** | **6.1** | **1-2 weeks** | ⏳ Next |
| **Glyph Rendering** | **6.2** | **2-3 weeks** | ⏳ Next |
| **Cell Attributes** | **6.3** | **1-2 weeks** | ⏳ Next |
| **Feature Complete** | **6.4** | **2-3 weeks** | ⏳ Next |
| **Optimization** | **6.5** | **1-2 weeks** | ⏳ Next |

## Success Criteria

### Phase 5 Deployment Success
- [x] IO thread operating stably for 24+ hours
- [x] No memory leaks detected (ASAN)
- [x] Lock-free queues performing under load
- [x] Frame update latency <100ms
- [x] All unit and integration tests passing

### Phase 6 Success (Future)
- [ ] OpenGL backend rendering correctly
- [ ] Feature parity with VTE3 backend
- [ ] 60 FPS frame rate maintained
- [ ] Performance exceeds VTE3 on complex terminals
- [ ] No visual artifacts or regressions

## Documentation and Knowledge Transfer

### Phase 6 Development
- Keep architecture documentation current
- Document OpenGL-specific decisions (ADRs)
- Create shader documentation (math, techniques)
- Publish performance analysis and benchmarks

### Phase 5 Maintenance
- Monitor production stability
- Track ASAN reports and fix any leaks
- Collect performance metrics for baseline
- Document any observed issues

---

**Created**: 2026-01-05
**Version**: 1.0
**For**: Phase 6 Planning and Implementation
**Status**: Ready for Phase 6 Kickoff
