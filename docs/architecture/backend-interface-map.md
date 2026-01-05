# Backend-Agnostic Interface Map (Draft)

## Goals
- Separate terminal core from UI toolkit and rendering backend.
- Support GTK3, GTK4, Qt, and headless or KMS/DRM paths.
- Allow GPU renderer selection (OpenGL now, Vulkan later).
- Keep IO, VT parsing, and scrollback independent of UI threads.

## Core Layers (proposed)
1. TerminalCore
   - VT parser, state machine, scrollback, hyperlinks, search index.
2. PTYBackend
   - Spawn, resize, signal, and IO pump for child processes.
3. RenderBackend
   - Glyph cache, rasterization, damage tracking, GPU or CPU compositor.
4. WindowBackend
   - Windowing, event loop integration, surface creation.
5. InputBackend
   - Keyboard, mouse, IME or compose, keymap translation.
6. ClipboardBackend
   - Primary or clipboard, selection ownership, drag and drop.
7. ConfigBackend
   - Config load, reload, keybinding dispatch, profile support.
8. IPCBackend
   - Remote control and automation (tabs, layouts, search, etc).
9. ExtensionBackend
   - Script hooks or plugins (kittens-like).
10. Diagnostics
   - Logging, crash reports, telemetry opt-in, benchmarks.
## Data Flow Sketch
AppMain -> WindowBackend -> InputBackend -> TerminalCore
TerminalCore -> RenderBackend -> WindowBackend surface
PTYBackend <-> TerminalCore (async IO thread)

## Interface Contracts (examples)
- TerminalCore:
  * processInput(bytes)
  * resize(cols, rows)
  * getRenderModel() -> RenderModel
- RenderBackend:
  * prepareFrame(RenderModel)
  * present()
- WindowBackend:
  * createWindow(RenderBackend)
  * runLoop()
  * requestRedraw()
- PTYBackend:
  * spawn(cmd, env, cwd)
  * write(bytes)
  * setResize(cols, rows)
## Backend Matrix (draft)
- GTK3: WindowBackend=GTK3, RenderBackend=OpenGL or Cairo, Input=GDK.
- GTK4: WindowBackend=GTK4, RenderBackend=OpenGL or Vulkan (GSK or custom),
  Input=GDK.
- Qt6: WindowBackend=Qt, RenderBackend=QOpenGL or QVulkan, Input=Qt.
- Wayland-only: WindowBackend=Wayland, RenderBackend=OpenGL or Vulkan,
  Input=libinput.
- X11: WindowBackend=Xlib or XCB, RenderBackend=OpenGL, Input=XKB.
- KMS/DRM: WindowBackend=DRM, RenderBackend=OpenGL or Vulkan, Input=libinput.
- Framebuffer: WindowBackend=fbdev, RenderBackend=CPU or OpenGL (if available),
  Input=evdev.

## VTE Interop (optional)
- VTE adapter that maps VTE surfaces to RenderBackend or bypasses core.
- Use only as a transitional backend during D-native VT parity.

## Implementation Status (Phase 0-2 Complete)

### Implemented Components (source/gx/tilix/backend/)
- `package.d` - Module exports for backend abstraction
- `render.d` - IRenderBackend interface, RenderModel, CellAttrs, CursorState
- `vte3.d` - VTE3RenderBackend (40 FPS cap, fallback backend)
- `opengl.d` - OpenGLRenderBackend with GtkGLArea and arbitrary Hz frame pacing
- `shaders.d` - GLSL vertex/fragment shaders for terminal and cursor rendering
- `atlas.d` - FontAtlas with atomic versioning for lock-free GPU sync

### RenderBackend Interface (implemented)
```d
interface IRenderBackend {
    void initialize(Widget container);
    void prepareFrame(ref const RenderModel model);
    void present();
    void resize(uint cols, uint rows);
    @property RenderCapabilities capabilities() const;
    @property bool isReady() const;
    void dispose();
}
```

### Frame Pacing Features (implemented)
- Arbitrary Hz support: 24/30/60/75/120/144/165/240/360+
- FramePacer with adaptive timing (sleep + spin-wait for precision)
- FrameStats tracking: FPS, dropped frames, min/max/avg frame times
- VSync and adaptive sync (G-Sync/FreeSync) support
- Native refresh rate detection via XRandR (no hardcoded Hz values)

### Font Atlas Features (implemented)
- Lock-free glyph caching with atomic versioning (Ghostty pattern)
- Row-based packing for efficient atlas usage
- Dirty region tracking for partial GPU updates
- Thread-safe rasterization with double-check locking
- FreeType glyph rasterization with real metrics (FT_Load_Char)
- Dynamic font loading via FT_New_Face

### Backend Selection
- Environment variable: TILIX_RENDERER=auto|vte3|opengl
- GSettings key: render-backend (auto/vte3/opengl)
- Auto-detect: OpenGL if available, graceful fallback to VTE3

### Build System
- DUB: Full OpenGL support via bindbc-opengl/freetype
- Meson: Graceful degradation (VTE3 only) via version guards
- Both builds pass with zero warnings (-w enforced)

### IO Thread Infrastructure (Phase 3 - implemented)
- `iothread.d` - IO thread separation following Ghostty pattern
- `IOMessage` - Tagged union for thread communication (Data, Resize, Close, Bell, Title)
- `LockFreeQueue` - SPSC atomic queue for minimal latency
- `DoubleBuffer` - Swap-based frame buffering
- `TerminalBufferState` - Cell grid with version tracking
- `IOThreadManager` - Lifecycle management with condition variables

### Palette System (Phase 4 - complete)
- `source/gx/tilix/theme/palette.d` - Ptyxis-compatible palette loading
- `Palette` struct with light/dark color scheme variants
- 16 ANSI colors + foreground/background + special indicators
- `parseHexColor()` - Hex to RGBA conversion (#RGB, #RRGGBB, #RRGGBBAA)
- `parsePaletteFile()` - INI-style palette file parser
- `PaletteManager` - Runtime palette selection and scheme switching
- 5 built-in palettes: Tango, Solarized Dark/Light, Dracula, Nord
- 10 palette files in `data/palettes/`:
  - tango, solarized-dark, solarized-light, dracula, nord
  - one-dark, gruvbox-dark, catppuccin-mocha, tokyo-night, rose-pine
- GSettings key: `palette-name` in Profile schema
- Installation: Palettes installed to `$pkgdatadir/palettes/`

### Palette UI Integration (Phase 4 - complete)
- Profile editor integration in `source/gx/tilix/prefeditor/profileeditor.d`
- Palette preset dropdown in ColorPage (before Color scheme dropdown)
- `onPalettePresetChanged()` - Handler for palette selection changes
- `applyPalettePreset()` - Applies palette colors to UI and GSettings
- `initPalettePresetCombo()` - Initializes combo from saved GSettings
- Automatic VTE color updates via existing GSettings listener in terminal.d
- Loads palettes from system (`$pkgdatadir/palettes/`) and user config

### OpenGL Shader Pipeline (Phase 2B - implemented)
- Shader compilation and linking via `shaders.d` (vertex/fragment)
- VAO/VBO setup with vertex attributes (position, texcoord, colors)
- Vertex data conversion from RenderModel to GPU format
- Cell struct with character and attributes in RenderModel
- Orthographic projection for 2D screen-space rendering

### X11 Native Refresh Detection (Phase 2D - implemented)
- `source/x11/Xrandr.d` - XRandR bindings for refresh rate query
- `source/x11/Xpresent.d` - XPresent bindings for hardware VSync
- `detectNativeRefreshRate()` - Queries active CRTC mode via XRandR
- Calculates Hz from dotClock/(hTotal*vTotal) timing data
- Automatic detection on backend initialization (no hardcoded values)

## Known Gaps (remaining)
- Font shaping and ligature pipeline (HarfBuzz integration)
- IO thread integration with PTY (iothread.d ready, needs terminal.d hookup)
- XPresent MSC-based frame timing (optional enhancement)
- Vi-mode scrollback (Phase 6)

## Next Steps
- Phase 5: Process indicators and tab previews
- Phase 6: Vi-mode and hints system
- Integration: Hook iothread.d into terminal.d PTY loop
