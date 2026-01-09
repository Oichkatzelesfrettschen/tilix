# Tilix Architecture Documentation

This directory contains architectural documentation and interface maps.

## Documents

| Document | Description |
|----------|-------------|
| [backend-interface-map.md](backend-interface-map.md) | Backend abstraction interface map |

## Architecture Overview

Tilix is designed with a layered architecture to support multiple backends:

### Core Layers

1. **TerminalCore** - VT parser, state machine, scrollback, hyperlinks, search
2. **PTYBackend** - Child process spawn, resize, signal, IO pump
3. **RenderBackend** - Glyph cache, rasterization, GPU/CPU compositor
4. **WindowBackend** - Windowing, event loop, surface creation
5. **InputBackend** - Keyboard, mouse, IME, keymap translation
6. **ClipboardBackend** - Selection, clipboard, drag-and-drop
7. **ConfigBackend** - Configuration, keybindings, profiles
8. **IPCBackend** - Remote control and automation
9. **ExtensionBackend** - Plugins and scripts
10. **Diagnostics** - Logging, crash reports, benchmarks

### Data Flow

```
AppMain → WindowBackend → InputBackend → TerminalCore
TerminalCore → RenderBackend → WindowBackend surface
PTYBackend ↔ TerminalCore (async IO thread)
```

## Backend Implementations

### Current

- **VTE3RenderBackend** - GTK3/VTE-based rendering (default)
- **OpenGLRenderBackend** - Custom OpenGL renderer (experimental)

### Planned

- GTK4/VTE4 backend
- Qt/QTermWidget backend
- Pure D backend (KMS/DRM)

## Related Documentation

- [Design Documents](../design/) - Architecture design specs
- [Audits](../audits/) - Including ARCHITECTURAL_AUDIT.md
- [Pure D Backend](../pure-d/) - Pure D implementation docs
