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

## Known Gaps
- Font shaping and ligature pipeline (HarfBuzz and FreeType).
- GPU text atlas and cache eviction strategy.
- Cursor rendering and selection layers decoupled from toolkit.

## Next Steps
- Define minimal D interfaces in source/terminal/*.
- Implement no-op backends for testing.
- Add conformance tests around VT and render model output.
