# Super Phase 6: Pure D High-Performance Terminal Architecture

## Executive Summary

Transform Tilix from a GTK/VTE-based terminal emulator to a **Pure D high-performance terminal** targeting **uncapped framerates (320Hz+)** by replacing GTK with bindbc-opengl/glfw, replacing VTE with arsd-official's terminalemulator, and adding SIMD optimization via mir-algorithm and intel-intrinsics.

---

## Current State Analysis (from Exploration)

### Coupling Assessment

| Component | GTK Coupling | Effort to Replace |
|-----------|--------------|-------------------|
| terminal.d | 37 imports, 30+ signals | HIGH - central hub |
| vte3container.d | 357 lines wrapping VTE | MEDIUM - replace entirely |
| prefeditor/ | Heavy GTK dialogs | MEDIUM - separate concern |
| application.d | GTK Application lifecycle | HIGH - replace with GLFW |

### What We Keep (Phase 0-5 Assets)

1. **iothread.d** (586 lines) - Lock-free SPSC queues, double-buffering
2. **state.d** (345 lines) - TerminalState, CellAttrs, Cell structs
3. **atlas.d** (588 lines) - Font atlas with FreeType, lock-free versioning
4. **shaders.d** (274 lines) - Vertex/fragment shaders (instanced rendering ready)
5. **opengl.d** (728 lines) - FramePacer (24Hz-360Hz), OpenGL backend (~70% complete)
6. **render.d** (190 lines) - IRenderBackend interface
7. **container.d** (365 lines) - IRenderingContainer abstraction (84 methods)

### What We Replace

1. **vtparser.d** -> **arsd.terminalemulator** (Pure D ANSI/VT state machine)
2. **vte3container.d** -> **PureDContainer** (new implementation)
3. **GTK event loop** -> **GLFW event loop**
4. **GTK widgets** -> **GLFW window + OpenGL rendering**

---

## Technology Stack

### Core Stack (Required)

| Library | Purpose | dub.json Name |
|---------|---------|---------------|
| arsd-official | Terminal emulation (VT parsing) | `arsd-official:terminal_emulator` |
| bindbc-opengl | OpenGL 4.5 bindings | `bindbc-opengl` |
| bindbc-glfw | Window/input management | `bindbc-glfw` |
| bindbc-freetype | Font rendering | `bindbc-freetype` |

### Optimization Stack (Performance)

| Library | Purpose | dub.json Name |
|---------|---------|---------------|
| mir-algorithm | D's ndslice (Eigen equivalent) | `mir-algorithm` |
| intel-intrinsics | Cross-compiler SIMD (AVX2) | `intel-intrinsics` |

### Optional Stack (Future)

| Library | Purpose | dub.json Name |
|---------|---------|---------------|
| capnproto-dlang | Zero-copy IPC | `capnproto-dlang` |
| bindbc-xcb | XRender/XPresent low-level | `bindbc-xcb` |

---

## Architecture Design

### Layer Diagram

```
+-----------------------------------------------------------+
|                    Application Layer                       |
|  main.d -> PureDTerminal (replaces GTK Application)       |
+-----------------------------------------------------------+
                              |
+-----------------------------------------------------------+
|                    Window Layer (GLFW)                     |
|  GLFWWindow -> keyboard/mouse events -> resize handling   |
+-----------------------------------------------------------+
                              |
+-----------------------------------------------------------+
|                  Terminal Emulation Layer                  |
|  arsd.terminalemulator.TerminalEmulator                   |
|  - ANSI/VT sequence parsing (CSI, OSC, DCS)               |
|  - UTF-8 decoding with proper combining char support      |
|  - Scrollback buffer management                           |
+-----------------------------------------------------------+
                              |
+-----------------------------------------------------------+
|                    State Layer (Keep)                      |
|  TerminalStateManager -> DoubleBuffer -> LockFreeQueue    |
|  (Already implemented in Phase 5 - reuse directly)        |
+-----------------------------------------------------------+
                              |
+-----------------------------------------------------------+
|                   Rendering Layer (OpenGL)                 |
|  OpenGLRenderBackend -> FontAtlas -> Shaders              |
|  - Instanced rendering (1-2 draw calls for entire grid)   |
|  - FramePacer for 320Hz+ with VSync bypass                |
|  - GPU glyph cache with LRU eviction                      |
+-----------------------------------------------------------+
                              |
+-----------------------------------------------------------+
|                  SIMD Optimization Layer                   |
|  mir-algorithm (ndslice) + intel-intrinsics (AVX2)        |
|  - Vectorized UTF-8 validation                            |
|  - SIMD cell attribute updates                            |
|  - Batch color conversion (sRGB <-> linear)               |
+-----------------------------------------------------------+
```

### Data Flow

```
PTY fd -> IOThread -> LockFreeQueue -> arsd.terminalemulator
                                              |
                                              v
                                    TerminalState (cells, cursor)
                                              |
                                              v
                            OpenGLRenderBackend.render(state)
                                              |
                                              v
                                    GLFW SwapBuffers (320Hz+)
```

---

## Implementation Phases

### Super Phase 6.0: Foundation (Week 1-2)

**Objective**: Minimal GLFW window with OpenGL context displaying static text.

**Tasks**:
1. Add bindbc-opengl, bindbc-glfw to dub.json
2. Create `source/gx/tilix/pure/` directory structure
3. Implement `GLFWWindow` wrapper class
4. Port existing OpenGL code to use bindbc-opengl
5. Render static "Hello World" with existing font atlas
6. Verify 320Hz+ frame timing with FramePacer

**Files to Create**:
- `source/gx/tilix/pure/window.d` - GLFW window management
- `source/gx/tilix/pure/context.d` - OpenGL context setup
- `source/gx/tilix/pure/main.d` - Pure D entry point

**Acceptance Criteria**:
- Window opens at 1920x1080
- OpenGL 4.5 context active
- Font atlas renders glyphs
- Frame time <3ms (>333 FPS potential)

**Status**: COMPLETE - pured/ module structure created

### Super Phase 6.1: Terminal Emulation (Week 3-4)

**Objective**: Integrate arsd.terminalemulator for VT parsing.

**Tasks**:
1. Add `arsd-official:terminal_emulator` to dub.json
2. Create adapter layer between arsd and our TerminalState
3. Wire PTY output through arsd.terminalemulator
4. Map arsd cell attributes to our CellAttrs struct
5. Handle scrollback buffer synchronization
6. Test with common ANSI sequences (colors, cursor, erase)

**Files to Create**:
- `source/gx/tilix/pure/emulator.d` - arsd adapter
- `source/gx/tilix/pure/adapter.d` - State translation layer

**Key Integration Points**:
```d
// Adapter from arsd.terminalemulator to our TerminalState
class TerminalEmulatorAdapter {
    import arsd.terminalemulator;
    TerminalEmulator emulator;
    TerminalStateManager stateManager;

    void processPtyData(const(ubyte)[] data) {
        emulator.send(cast(char[])data);
        syncStateToManager();
    }

    void syncStateToManager() {
        auto writeBuffer = stateManager.getWriteBuffer();
        foreach (row; 0 .. emulator.scrollbackHeight + emulator.height) {
            foreach (col; 0 .. emulator.width) {
                auto cell = emulator[col, row];
                writeBuffer.cells[row * writeBuffer.cols + col] =
                    Cell(cell.ch, translateAttrs(cell.attrs));
            }
        }
        stateManager.swap();
    }
}
```

**Acceptance Criteria**:
- `ls --color` displays colors correctly
- `vim` renders and accepts input
- Cursor positioning works
- Scrollback accessible

**Status**: COMPLETE - pured/emulator.d created with PureDEmulator class

### Super Phase 6.2: Input Handling (Week 5)

**Objective**: Complete keyboard/mouse input via GLFW.

**Tasks**:
1. Map GLFW key codes to terminal escape sequences
2. Implement modifier key handling (Ctrl, Alt, Shift)
3. Handle mouse events (button, scroll, motion)
4. Support bracketed paste mode
5. Implement focus in/out events
6. Test with interactive programs (vim, htop, mc)

**Files to Create**:
- `source/gx/tilix/pure/input.d` - Input translation
- `source/gx/tilix/pure/keymap.d` - Key code mapping

**Acceptance Criteria**:
- All printable characters work
- Ctrl+C sends SIGINT
- Arrow keys work in applications
- Mouse reporting functional

**Status**: COMPLETE - pured/platform/input.d created with full GLFW input handling

### Super Phase 6.3: Widget System (Week 6)

**Objective**: Create Pure D widget system for UI composition.

**Tasks**:
1. Implement Widget base class with measure/arrange protocol
2. Create Container classes (StackPanel, Grid, DockPanel)
3. Implement event routing (bubble/tunnel)
4. Create Signal/Slot pattern for type-safe callbacks
5. Build TerminalWidget integrating emulator + renderer
6. Add Selection and Scrollback viewport management

**Files Created**:
- `pured/widget/base.d` - Widget base class, RootWidget, RenderContext
- `pured/widget/container.d` - Container, StackPanel, ContentControl
- `pured/widget/events.d` - Event hierarchy, MouseEvent, KeyEvent, etc.
- `pured/widget/layout.d` - Grid, DockPanel, WrapPanel, Canvas, UniformGrid
- `pured/widget/scrollbar.d` - Scrollbar, ScrollViewer
- `pured/widget/terminal.d` - TerminalWidget
- `pured/util/signal.d` - Signal/Slot implementation
- `pured/terminal/selection.d` - Text selection with word/line boundaries
- `pured/terminal/scrollback.d` - Scrollback viewport management

**Acceptance Criteria**:
- Widget layout protocol works (measure/arrange)
- Event routing functional
- TerminalWidget renders cells and handles input
- Selection and scrollback work

**Status**: COMPLETE - All widget modules build successfully

### Super Phase 6.4: SIMD Optimization (Week 7)

**Objective**: Vectorize hot paths with mir-algorithm and intel-intrinsics.

**Tasks**:
1. Add mir-algorithm, intel-intrinsics to dub.json
2. Replace cell buffer with mir ndslice
3. Vectorize UTF-8 validation (AVX2)
4. Batch attribute updates with SIMD
5. Optimize color space conversion (sRGB <-> linear)
6. Profile and measure improvements

**Files to Create**:
- `source/gx/tilix/pure/simd.d` - SIMD utilities
- `source/gx/tilix/pure/vectorized.d` - Vectorized operations

**Key Optimizations**:
```d
// Vectorized UTF-8 validation with intel-intrinsics
import intel_intrinsics;

bool validateUtf8Simd(const(ubyte)[] data) @nogc nothrow {
    // Process 32 bytes at a time with AVX2
    auto vec = __m256i.load(data.ptr);
    // ... SIMD validation logic
}

// mir ndslice for cell buffer
import mir.ndslice;

alias CellGrid = Slice!(Cell*, 2);

CellGrid allocateCellGrid(size_t cols, size_t rows) {
    return slice!Cell(rows, cols);
}
```

**Acceptance Criteria**:
- >50% throughput improvement on UTF-8 heavy workloads
- Zero allocations in render hot path
- Maintained correctness (all tests pass)

**Status**: NOT STARTED

### Super Phase 6.5: Advanced Rendering (Week 8-9)

**Objective**: Production-quality rendering with all features.

**Tasks**:
1. Implement selection highlighting
2. Add URL detection and underline rendering
3. Implement search highlighting
4. Add cursor blinking with configurable shapes
5. Support font ligatures (optional)
6. Implement true-color (24-bit) palette
7. Add bold/italic/underline rendering variants

**Files to Modify**:
- `source/gx/tilix/backend/opengl/opengl.d` - Extended rendering
- `source/gx/tilix/backend/opengl/shaders.d` - Additional shaders

**Acceptance Criteria**:
- Visual parity with VTE3 backend
- All SGR attributes render correctly
- Selection/search highlighting works
- Ligatures render if font supports them

**Status**: NOT STARTED

### Super Phase 6.6: Integration & Polish (Week 10-12)

**Objective**: Full integration, testing, and documentation.

**Tasks**:
1. Create backend switching mechanism (VTE3 vs PureD)
2. Port configuration loading (themes, fonts, keybindings)
3. Implement clipboard integration (X11/Wayland)
4. Add hyperlink support (OSC 8)
5. Write comprehensive tests
6. Performance benchmarking vs VTE3
7. Documentation and migration guide

**Files to Create**:
- `source/gx/tilix/pure/clipboard.d` - Clipboard integration
- `source/gx/tilix/pure/config.d` - Configuration loading
- `docs/SUPER_PHASE_6_COMPLETE.md` - Final documentation

**Acceptance Criteria**:
- Feature parity with VTE3 backend
- 320Hz+ sustained framerate
- <1ms input latency
- All unit tests pass
- ASAN clean

**Status**: NOT STARTED

---

## dub.json Changes

```json
{
    "dependencies": {
        "bindbc-opengl": "~>1.1.0",
        "bindbc-glfw": "~>1.1.0",
        "bindbc-freetype": "~>1.2.0",
        "arsd-official:terminal_emulator": "~>13.0.0",
        "mir-algorithm": "~>3.21.0",
        "intel-intrinsics": "~>2.5.0"
    },
    "subConfigurations": {
        "bindbc-opengl": "gl45",
        "bindbc-glfw": "static"
    },
    "dflags-ldc": ["-mcpu=native", "-O3", "-release"],
    "versions": ["PURE_D_BACKEND"]
}
```

---

## Migration Strategy

### Parallel Development

1. **Keep VTE3 backend functional** during development
2. **Add PURE_D_BACKEND version flag** for conditional compilation
3. **Share common code** (iothread.d, state.d, atlas.d, shaders.d)
4. **Gradual feature migration** with A/B testing

### Compilation Modes

```bash
# VTE3 backend (current, stable)
dub build

# Pure D backend (new, experimental)
dub build --config=pure-d

# Pure D with optimizations
dub build --config=pure-d --compiler=ldc2 --build=release-nobounds
```

### Rollback Plan

If Super Phase 6 encounters critical issues:
1. Remove `PURE_D_BACKEND` version flag
2. Build defaults to VTE3 backend
3. All Phase 0-5 code remains functional
4. Zero impact on existing users

---

## Performance Targets

| Metric | VTE3 (Current) | Super Phase 6 Target |
|--------|----------------|---------------------|
| Max FPS | 40 (hardcoded) | 320+ (uncapped) |
| Frame time | 25ms | <3ms |
| Input latency | ~50ms | <1ms |
| UTF-8 throughput | ~50 MB/s | >200 MB/s (SIMD) |
| Memory per cell | ~32 bytes | ~16 bytes |
| Startup time | ~500ms | <100ms |

---

## Risk Assessment

### High Risk
- **arsd.terminalemulator compatibility**: May need patches for edge cases
- **GLFW on Wayland**: Requires XWayland or native Wayland port

### Medium Risk
- **Font rendering differences**: FreeType vs Pango may differ
- **Input method support**: Complex input (CJK) needs careful handling

### Low Risk
- **OpenGL compatibility**: GL 4.5 widely supported
- **Performance targets**: Already demonstrated in existing code

---

## Success Criteria

1. **Functional**: All VTE3 features work in Pure D backend
2. **Performance**: 320Hz+ sustained, <1ms input latency
3. **Quality**: ASAN clean, all tests pass, no visual regressions
4. **Maintainability**: Clean separation, documented architecture
5. **Compatibility**: Works on X11, XWayland, major distros

---

## Progress Summary

### Completed (as of 2026-01-05)

- [x] Phase 6.0: Foundation - GLFW window, OpenGL context
- [x] Phase 6.1: Terminal Emulation - arsd adapter
- [x] Phase 6.2: Input Handling - GLFW key/mouse translation
- [x] Phase 6.3: IPC + search UX - expanded IPC commands (tabs/splits) + live search overlay text
- [x] Phase 6.3: Widget System - Full widget hierarchy

### Files Created

```
pured/
├── package.d              # Main module exports
├── window.d               # GLFW window wrapper
├── context.d              # OpenGL context setup
├── pty.d                  # PTY management
├── emulator.d             # arsd.terminalemulator adapter
├── fontatlas.d            # Font atlas with FreeType
├── renderer.d             # Cell renderer
├── platform/
│   ├── package.d
│   └── input.d            # Input handling
├── terminal/
│   ├── package.d
│   ├── selection.d        # Text selection
│   └── scrollback.d       # Scrollback viewport
├── widget/
│   ├── package.d
│   ├── base.d             # Widget base class
│   ├── container.d        # Container widgets
│   ├── events.d           # Event system
│   ├── layout.d           # Layout containers
│   ├── scrollbar.d        # Scrollbar widgets
│   └── terminal.d         # Terminal widget
└── util/
    ├── package.d
    └── signal.d           # Signal/slot pattern
```

### Remaining Work

- [ ] Phase 6.4: SIMD Optimization
- [ ] Phase 6.5: Advanced Rendering
- [ ] Phase 6.6: Integration & Polish
- [ ] Tabs/splits UI
- [ ] Preferences dialog
- [ ] Profile management
- [ ] Search functionality
- [ ] Hyperlink detection

### Estimated Feature Parity: ~15-20%

---

**Prepared**: 2026-01-05
**Version**: 1.1
**Status**: Phase 6.3 Complete
**Estimated Remaining Duration**: 6-8 weeks
